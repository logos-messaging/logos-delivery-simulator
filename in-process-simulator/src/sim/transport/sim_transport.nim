## In-process transport for the simulator.
##
## Why not libp2p's own `MemoryTransport` (libp2p/transports/memorytransport.nim):
##
## 1. **It deadlocks under yamux.** Its pipe is `bridgedConnections`, whose
##    `BufferStream.readQueue` has capacity **1** (bufferstream.nim:48), so a
##    write blocks until the peer's read loop consumes it. Yamux writes its
##    initial frames in both directions before either side starts reading, and
##    the two ends block on each other. Measured on libp2p 2.3.1: gossipsub over
##    {yamux, memory} fails to upgrade, while {yamux, tcp}, {mplex, memory} and
##    {mplex, tcp} all work -- TCP survives only because the kernel socket
##    buffer absorbs the initial burst. A real socket is buffered, so we buffer
##    too (`SimBufferCap`), which is both more faithful and deadlock-free.
## 2. **Its listener is single-shot.** `MemoryListener.dial` deletes the listener
##    from the global table *before* completing the accept future
##    (memorymanager.nim:45-47), so a dial landing between two `accept()` calls
##    raises "No memory listener found". We keep a persistent listener holding a
##    queue of pending connections, which removes the race by construction --
##    and with it the per-target dial lock and retry loop it would have forced.
## 3. **A duplicate address silently deafens a node.** `accept` raises "Memory
##    address already in use", which `Switch.accept` swallows as
##    "Exception in accept loop, exiting" (switch.nim:319-323): the node stays
##    "started" but never accepts again. We reject duplicates at registration,
##    loudly, before anything starts.
## 4. **It leaks.** `MemoryTransport.connections` is appended on every accept and
##    dial and never pruned.
##
## We also need per-edge byte counters (for the bandwidth metric) and a seam for
## simulated link delay, neither of which can be bolted onto libp2p's version:
## `BridgeStream.writeHandler` is private (bridgestream.nim:16). Subclassing the
## public `BufferStream` is the supported way in.
##
## Addresses reuse the already-registered `/memorytransport/<name>` codec
## (multiaddress.nim:490), so no new multicodec has to be registered.

{.push raises: [].}

import std/[tables, sequtils]
import chronos, chronicles, results
import libp2p/[multiaddress, multicodec, builders]
import libp2p/stream/[connection, bufferstream]
import libp2p/transports/transport
import libp2p/upgrademngrs/upgrade

export transport, connection

logScope:
  topics = "sim transport"

const
  SimBufferCap* = 64
    ## Queued writes allowed before a sender blocks, standing in for a socket
    ## send buffer. Must be > 1 or yamux deadlocks on upgrade (see above).
    ## Backpressure still exists, just further out.

type
  SimTransportError* = object of transport.TransportError

  SimStream* = ref object of BufferStream
    ## One end of an in-process pipe. Writes are pushed straight into the
    ## peer's read queue -- no syscall, no copy beyond the seq itself.
    peer*: SimStream
    writeLock: AsyncLock
    bytesWritten*: uint64
    msgsWritten*: uint64
    edgeId*: uint32
      ## Identifies the edge for per-edge accounting; set by the harness.

  SimListener* = ref object
    address: string
    pending: AsyncQueue[RawConn]
    closed: bool

  SimTransport* = ref object of Transport
    listener: SimListener
    conns: seq[RawConn]

  SimRegistry = ref object
    listeners: Table[string, SimListener]

# ---------------------------------------------------------------------------
# Registry. Process-global by nature: it is what stands in for "the network".
# Single-threaded by construction (one chronos dispatcher), so no lock.
# ---------------------------------------------------------------------------

var gRegistry {.threadvar.}: SimRegistry

proc registry(): SimRegistry =
  if gRegistry.isNil:
    gRegistry = SimRegistry(listeners: initTable[string, SimListener]())
  gRegistry

proc simReset*() =
  ## Drop all listeners. For tests that build several networks in one process.
  gRegistry = nil

proc simListenerCount*(): int =
  registry().listeners.len

# ---------------------------------------------------------------------------
# SimStream
# ---------------------------------------------------------------------------

method initStream*(s: SimStream) =
  if s.objName.len == 0:
    s.objName = "SimStream"
  procCall BufferStream(s).initStream()
  # The whole point: replace the capacity-1 queue the base class installs.
  s.readQueue = newAsyncQueue[seq[byte]](SimBufferCap)

method write*(
    s: SimStream, msg: sink seq[byte]
): Future[void] {.async: (raises: [CancelledError, LPStreamError]).} =
  if s.peer.isNil:
    raise newLPStreamClosedError()
  s.bytesWritten += uint64(msg.len)
  s.msgsWritten += 1
  # pushData asserts that only one push is in flight per stream, so writes to a
  # given peer must be serialized.
  await s.writeLock.acquire()
  try:
    # SEAM: simulated link delay hooks in here, once the delay wheel lands.
    # It must not `sleepAsync` inline -- that would serialize the whole edge.
    await s.peer.pushData(move(msg))
  finally:
    # release() only raises if the lock is not held, which cannot happen here.
    try:
      s.writeLock.release()
    except AsyncLockError:
      raiseAssert "writeLock released while held"

method closeImpl*(s: SimStream): Future[void] {.async: (raises: []).} =
  let p = s.peer
  s.peer = nil
  if not p.isNil and not p.isClosed:
    try:
      await p.pushEof()
    except CancelledError, LPStreamError:
      discard
  await procCall BufferStream(s).closeImpl()

method getWrapped*(s: SimStream): Connection =
  nil

proc bridgedPair(dirA, dirB: Direction): (SimStream, SimStream) =
  ## A connected pair of in-process stream ends.
  let a = SimStream(writeLock: newAsyncLock())
  let b = SimStream(writeLock: newAsyncLock())
  a.dir = dirA
  b.dir = dirB
  # timeout 0 => no per-connection timeoutMonitor task. At 3000 nodes those
  # suspended futures are a real cost (connection.nim:78-88) and the simulator
  # has no idle connections to reap.
  a.timeout = 0.seconds
  b.timeout = 0.seconds
  a.initStream()
  b.initStream()
  a.peer = b
  b.peer = a
  (a, b)

# ---------------------------------------------------------------------------
# SimTransport
# ---------------------------------------------------------------------------

proc new*(T: typedesc[SimTransport], upgrade: Upgrade = Upgrade()): T =
  let self = T(upgrader: upgrade)
  procCall Transport(self).initialize()
  self

method handles*(self: SimTransport, ma: MultiAddress): bool {.gcsafe, raises: [].} =
  if procCall Transport(self).handles(ma):
    if ma.protocols.isOk:
      return Memory.match(ma)
  false

method start*(
    self: SimTransport, addrs: seq[MultiAddress]
) {.async: (raises: [LPError, transport.TransportError, CancelledError]).} =
  if self.running:
    return
  if addrs.len != 1:
    raise newException(
      SimTransportError,
      "SimTransport needs exactly one address, got " & $addrs.len)

  let key = $addrs[0]
  let reg = registry()
  if key in reg.listeners:
    # Fail loudly at start, rather than the way libp2p's version fails: by
    # killing the accept loop later with a single log line.
    raise newException(SimTransportError, "sim address already in use: " & key)

  self.listener = SimListener(
    address: key, pending: newAsyncQueue[RawConn](SimBufferCap))
  reg.listeners[key] = self.listener

  self.addrs = addrs
  self.running = true
  self.onRunning.fire()

method stop*(self: SimTransport) {.async: (raises: []).} =
  if not self.running:
    return
  self.running = false
  self.onStop.fire()

  if not self.listener.isNil:
    self.listener.closed = true
    registry().listeners.del(self.listener.address)
    self.listener = nil

  let conns = self.conns
  self.conns = @[]
  await noCancel allFutures(conns.mapIt(it.close()))

method accept*(
    self: SimTransport
): Future[RawConn] {.async: (raises: [transport.TransportError, CancelledError]).} =
  if not self.running or self.listener.isNil:
    raise newTransportClosedError()
  let conn =
    try:
      await self.listener.pending.popFirst()
    except CancelledError as e:
      raise e
  self.conns.add(conn)
  # Prune closed entries so `conns` cannot grow without bound over a long run.
  self.conns.keepItIf(not it.isClosed)
  conn

method dial*(
    self: SimTransport,
    hostname: string,
    ma: MultiAddress,
    peerId: Opt[PeerId] = Opt.none(PeerId),
    dir: Direction = Direction.Out,
): Future[RawConn] {.async: (raises: [transport.TransportError, CancelledError]).} =
  if not self.running:
    raise newTransportClosedError()

  let key = $ma
  let reg = registry()
  if key notin reg.listeners:
    raise newException(SimTransportError, "no sim listener at " & key)
  let l =
    try:
      reg.listeners[key]
    except KeyError:
      raiseAssert "checked with in"
  if l.closed:
    raise newException(SimTransportError, "sim listener closed at " & key)

  let (inbound, outbound) = bridgedPair(Direction.In, Direction.Out)
  # The listener persists, so this never races an accept loop that is between
  # iterations: the connection simply waits in the queue.
  try:
    await l.pending.addLast(inbound)
  except CancelledError as e:
    raise e
  self.conns.add(outbound)
  self.conns.keepItIf(not it.isClosed)
  outbound

proc simAddress*(name: string): MultiAddress {.raises: [LPError, ValueError].} =
  ## Deterministic address for node `name`. Deliberately not the
  ## `/memorytransport/*` wildcard: that resolves to a random address at start
  ## and leaves both it and the wildcard in peerInfo.listenAddrs, so a topology
  ## could not be computed before the nodes are up.
  MultiAddress.init("/memorytransport/" & name).tryGet()

proc withSimTransport*(b: SwitchBuilder): SwitchBuilder =
  ## Install the simulator transport on a SwitchBuilder, mirroring libp2p's own
  ## `withMemoryTransport` (builders.nim:262) but with our transport.
  b.withTransport(
    proc(config: TransportConfig): Transport =
      SimTransport.new(config.upgr)
  )
