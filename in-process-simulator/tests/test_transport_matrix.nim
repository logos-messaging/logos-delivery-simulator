## Isolation probe 2: plain libp2p GossipSub (no waku) over the stock memory
## transport, both sides mounted, connected with switch.connect() -- the exact
## shape m1a uses. Distinguishes "WakuRelay problem" from "bidirectional
## gossipsub over a bridged in-memory connection" problem.
import std/[strformat, sequtils, tables, sets]
import chronos, results, stew/byteutils
import libp2p/[builders, switch, multiaddress]
import libp2p/protocols/pubsub/[gossipsub, pubsub]
import libp2p/crypto/crypto as lpcrypto

const Topic = "test-topic"

proc mk(idx: int, rng: lpcrypto.Rng, yamux: bool, tcp: bool): (Switch, GossipSub) =
  let a =
    if tcp: MultiAddress.init("/ip4/127.0.0.1/tcp/0").tryGet()
    else: MultiAddress.init(&"/memorytransport/g{idx}").tryGet()
  var b = SwitchBuilder.new().withRng(rng).withAddress(a).withNoise()
  b = if tcp: b.withTcpTransport() else: b.withMemoryTransport()
  b = if yamux: b.withYamux() else: b.withMplex()
  let sw = b.build()
  let g = GossipSub.init(switch = sw, triggerSelf = false, rng = rng)
  sw.mount(g)
  (sw, g)

proc run(yamux: bool, tcp: bool) {.async.} =
  let rng = lpcrypto.newRng()
  let (swA, gA) = mk(0, rng, yamux, tcp)
  let (swB, gB) = mk(1, rng, yamux, tcp)
  var got = newSeq[string]()
  proc hB(topic: string, data: seq[byte]) {.async.} =
    got.add(string.fromBytes(data))
  await swA.start()
  await swB.start()
  gA.subscribe(Topic, proc(t: string, d: seq[byte]) {.async.} = discard)
  gB.subscribe(Topic, hB)

  let dialAddr =
    if tcp: swB.peerInfo.listenAddrs[0]
    else: MultiAddress.init("/memorytransport/g1").tryGet()
  echo "--- muxer=", (if yamux: "yamux" else: "mplex"),
       " transport=", (if tcp: "tcp" else: "memory"), " ---"
  await swA.connect(swB.peerInfo.peerId, @[dialAddr])
  echo "connected"
  await sleepAsync(2.seconds)
  echo "A mesh=", gA.mesh.getOrDefault(Topic).len, " B mesh=", gB.mesh.getOrDefault(Topic).len
  discard await gA.publish(Topic, toBytes("hi"))
  await sleepAsync(1.seconds)
  echo "B got: ", got
  echo (if got == @["hi"]: "GOSSIP-OVER-MEMORY PASS" else: "GOSSIP-OVER-MEMORY FAIL")
  await swA.stop(); await swB.stop()

when isMainModule:
  import std/os
  let yamux = paramStr(1) == "yamux"
  let tcp = paramStr(2) == "tcp"
  try: waitFor run(yamux, tcp)
  except CatchableError as e: echo "FAILED: ", e.msg
