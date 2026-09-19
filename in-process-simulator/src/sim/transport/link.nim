## Link impairment model for SimTransport.
##
## Models a link the way gossipsub actually experiences one, rather than
## simulating TCP's control loop:
##
##   serialization delay = bytes / bandwidth   -- blocks the SENDER (backpressure)
##   propagation delay   = one-way latency     -- delays ARRIVAL, does not block
##
## That split is what matters: a sender is throttled by link capacity while
## several messages stay in flight, which a naive "sleep then deliver" model
## gets wrong (it would cap an edge at 1/RTT messages per second).
##
## Deliberately NOT modelled: cwnd dynamics (slow start, congestion collapse).
## The stream is reliable and ordered, so packet *loss* is not representable
## either -- real loss on a TCP link shows up as a latency spike from
## retransmission, which is what `retransmitRate`/`rto` produce.
##
## Timing floor: chronos computes its poll timeout in whole milliseconds, so
## delays below ~1ms are not representable. Intra-datacenter RTT (0.1-0.5ms)
## can only be modelled as 0 or over-estimated as 1ms.

{.push raises: [].}

import std/[heapqueue, random, deques]
import chronos

type
  LinkParams* = object
    propDelay*: Duration      ## one-way propagation delay
    jitter*: Duration         ## uniform +/- applied to propDelay
    bandwidthBps*: uint64     ## bits/sec; 0 = unlimited (no serialization delay)
    backlogCapBytes*: int     ## sender blocks once this much is queued on the edge
    retransmitRate*: float    ## P(extra RTO-sized delay), models TCP retransmit
    rto*: Duration

proc noImpairment*(): LinkParams =
  LinkParams(
    propDelay: ZeroDuration, jitter: ZeroDuration, bandwidthBps: 0,
    backlogCapBytes: 256 * 1024, retransmitRate: 0.0, rto: ZeroDuration)

proc isIdeal*(p: LinkParams): bool =
  ## Fast path: with no delay and no bandwidth cap the wheel is bypassed
  ## entirely, keeping the zero-impairment case as cheap as before.
  p.propDelay == ZeroDuration and p.jitter == ZeroDuration and
    p.bandwidthBps == 0 and p.retransmitRate <= 0.0

# ---------------------------------------------------------------------------
# Delay wheel
# ---------------------------------------------------------------------------

type
  DeliverProc* = proc(data: seq[byte]) {.gcsafe, raises: [].}

  Pending = object
    dueAt: Moment
    seqNo: uint64          ## tie-break, keeps FIFO order within one instant
    deliver: DeliverProc
    data: seq[byte]

  DelayWheel* = ref object
    ## One global min-heap drained by a single task. Deliberately not a task
    ## per edge: at 3000 nodes x degree 30 that would be 90k persistent tasks.
    heap: HeapQueue[Pending]
    wakeup: AsyncEvent
    running: bool
    counter: uint64
    task: Future[void]
    rng*: Rand

proc `<`(a, b: Pending): bool =
  if a.dueAt == b.dueAt: a.seqNo < b.seqNo else: a.dueAt < b.dueAt

var gWheel {.threadvar.}: DelayWheel

proc drainLoop(w: DelayWheel) {.async: (raises: []).} =
  while w.running:
    if w.heap.len == 0:
      w.wakeup.clear()
      try:
        await w.wakeup.wait()
      except CancelledError:
        return
      continue
    let now = Moment.now()
    if w.heap[0].dueAt > now:
      try:
        await sleepAsync(w.heap[0].dueAt - now)
      except CancelledError:
        return
      continue
    # Deliver everything now due.
    while w.heap.len > 0 and w.heap[0].dueAt <= Moment.now():
      let p = w.heap.pop()
      p.deliver(p.data)

proc wheel*(): DelayWheel =
  if gWheel.isNil:
    gWheel = DelayWheel(
      heap: initHeapQueue[Pending](), wakeup: newAsyncEvent(),
      running: true, rng: initRand(0x5EED))
    gWheel.task = gWheel.drainLoop()
  gWheel

proc wheelReset*() =
  if not gWheel.isNil:
    gWheel.running = false
    gWheel.wakeup.fire()
  gWheel = nil

proc schedule*(w: DelayWheel, at: Moment, deliver: DeliverProc, data: sink seq[byte]) =
  inc w.counter
  w.heap.push(Pending(dueAt: at, seqNo: w.counter, deliver: deliver, data: data))
  w.wakeup.fire()

proc pendingCount*(w: DelayWheel): int =
  w.heap.len

# ---------------------------------------------------------------------------
# Per-edge scheduling state
# ---------------------------------------------------------------------------

type EdgeClock* = object
  ## Tracks when the link next goes idle, so concurrent writes queue behind one
  ## another at link rate instead of each paying the delay independently.
  nextFreeAt*: Moment
  initialised*: bool

proc serializationNs(p: LinkParams, nbytes: int): int64 =
  if p.bandwidthBps == 0: 0'i64
  else: int64((uint64(nbytes) * 8_000_000_000'u64) div p.bandwidthBps)

proc scheduleSend*(
    ec: var EdgeClock, p: LinkParams, nbytes: int, rng: var Rand
): tuple[arriveAt: Moment, backlog: Duration] =
  ## Returns when the bytes land at the far end, and how far behind the link
  ## currently is (the caller uses that for backpressure).
  let now = Moment.now()
  if not ec.initialised or ec.nextFreeAt < now:
    ec.nextFreeAt = now
    ec.initialised = true

  let startAt = ec.nextFreeAt
  ec.nextFreeAt = startAt + nanoseconds(serializationNs(p, nbytes))

  var prop = p.propDelay
  if p.jitter != ZeroDuration:
    let j = p.jitter.nanoseconds
    prop = prop + nanoseconds(rng.rand(2 * j) - j)
  if p.retransmitRate > 0.0 and rng.rand(1.0) < p.retransmitRate:
    prop = prop + p.rto
  if prop < ZeroDuration:
    prop = ZeroDuration

  (ec.nextFreeAt + prop, ec.nextFreeAt - now)
