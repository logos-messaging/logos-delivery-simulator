## M1b -- N real WakuRelay nodes in a ring over SimTransport.
## Measures the two numbers M1 is supposed to produce: per-node startup cost and
## per-edge wiring cost (dominated by the Noise XX handshake, which is the thing
## that makes topology construction crypto-bound rather than I/O-bound).

import std/[times, strformat, sequtils, monotimes]
import chronos, results, stew/byteutils
import libp2p/crypto/crypto as lpcrypto
import sim/node

const
  Topic = "/waku/2/rs/2/0"
  MaxConns = 32

proc run(n: int) {.async.} =
  let rng = lpcrypto.newRng()
  var delivered = 0
  var nodes: seq[SimNode]

  let tBuild = getMonoTime()
  for i in 0 ..< n:
    let node = newSimNode(i, rng, MaxConns)
    node.onDeliver = proc(nd: SimNode, t: PubsubTopic, m: WakuMessage) {.gcsafe, raises: [].} =
      delivered += 1
    nodes.add(node)
  let buildMs = (getMonoTime() - tBuild).inMicroseconds.float / 1000.0

  let tStart = getMonoTime()
  await allFutures(nodes.mapIt(it.start()))
  let startMs = (getMonoTime() - tStart).inMicroseconds.float / 1000.0

  for node in nodes:
    node.subscribe(Topic)

  # Ring: i -> i+1, closing back to 0. Sequential on purpose here, so the
  # per-edge number is clean rather than an average over overlapped dials.
  let tWire = getMonoTime()
  for i in 0 ..< n:
    await nodes[i].connectTo(nodes[(i + 1) mod n])
  let wireMs = (getMonoTime() - tWire).inMicroseconds.float / 1000.0

  # Let gossipsub graft. Heartbeat is 1s, so a few rounds.
  await sleepAsync(chronos.seconds(4))
  let meshes = nodes.mapIt(it.meshSize(Topic))

  delivered = 0
  let msg = WakuMessage(payload: toBytes("m1b"), contentTopic: "/sim/1/t/proto")
  let tPub = getMonoTime()
  discard await nodes[0].relay.publish(Topic, msg)
  await sleepAsync(chronos.seconds(3))
  let propMs = (getMonoTime() - tPub).inMicroseconds.float / 1000.0

  echo &"N={n}"
  echo &"  construct : {buildMs:8.1f} ms total  ({buildMs/n.float:6.3f} ms/node)"
  echo &"  start     : {startMs:8.1f} ms total  ({startMs/n.float:6.3f} ms/node)"
  echo &"  wire      : {wireMs:8.1f} ms total  ({wireMs/n.float:6.3f} ms/edge)  [{n} edges]"
  echo &"  mesh      : min={meshes.min} max={meshes.max} avg={meshes.foldl(a+b).float/n.float:.2f}"
  echo &"  delivered : {delivered}/{n} nodes (publisher included, triggerSelf=true)"
  echo &"  window    : {propMs:.0f} ms"
  if delivered == n: echo "  M1b PASS" else: echo "  M1b FAIL"

  await allFutures(nodes.mapIt(it.stop()))
  simReset()

when isMainModule:
  import std/[os, strutils]
  let n = if paramCount() >= 1: parseInt(paramStr(1)) else: 10
  waitFor run(n)
