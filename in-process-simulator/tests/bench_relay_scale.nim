## M2 -- the scaling curve. Answers "how many real relay nodes fit on this
## machine, and up to what N do the latency numbers still mean anything".
##
## Payload carries (seq: u32, publishNs: u64) so a receiving node computes
## latency with no hashing and no lookup -- see the plan's R7.

import std/[strformat, sequtils, monotimes, times, random, algorithm, math]
import chronos, results
import libp2p/crypto/crypto as lpcrypto
import sim/[node, topology, probes]

const
  Topic = "/waku/2/rs/2/0"
  HeaderBytes = 12

proc encodeHeader(seqNo: uint32, publishNs: uint64, payloadBytes: int): seq[byte] =
  result = newSeq[byte](max(payloadBytes, HeaderBytes))
  for i in 0 .. 3:
    result[i] = byte((seqNo shr (8 * uint32(i))) and 0xFF)
  for i in 0 .. 7:
    result[4 + i] = byte((publishNs shr (8 * uint64(i))) and 0xFF)

proc decodeHeader(b: seq[byte]): tuple[seqNo: uint32, publishNs: uint64] =
  if b.len < HeaderBytes: return (0'u32, 0'u64)
  var s: uint32
  for i in 0 .. 3: s = s or (uint32(b[i]) shl (8 * uint32(i)))
  var t: uint64
  for i in 0 .. 7: t = t or (uint64(b[4 + i]) shl (8 * uint64(i)))
  (s, t)

proc nowNs(): uint64 = uint64(getMonoTime().ticks)

proc run(n, degree, msgCount, intervalMs, payloadBytes, drainSec: int, seed: int64) {.async.} =
  let rng = lpcrypto.newRng()
  var nodes: seq[SimNode]
  var recvCount = newSeq[int](msgCount)   # how many nodes got message k
  var latencies = newSeqOfCap[float](n * msgCount)

  echo &"=== N={n} degree={degree} msgs={msgCount} @{intervalMs}ms payload={payloadBytes}B ==="

  let t0 = getMonoTime()
  for i in 0 ..< n:
    let node = newSimNode(i, rng, maxConnections = degree * 2 + 8)
    node.onDeliver = proc(nd: SimNode, t: PubsubTopic, m: WakuMessage) {.gcsafe, raises: [].} =
      let (s, pubNs) = decodeHeader(m.payload)
      if int(s) < recvCount.len:
        recvCount[int(s)] += 1
        latencies.add(float(nowNs() - pubNs) / 1_000_000.0)
    nodes.add(node)
  await allFutures(nodes.mapIt(it.start()))
  for nd in nodes: nd.subscribe(Topic)
  let setupMs = (getMonoTime() - t0).inMicroseconds.float / 1000.0

  let edges = randomRegular(n, degree, seed)
  let (dmin, dmax, davg) = degreeStats(n, edges)

  let tw = getMonoTime()
  for e in edges:
    await nodes[e.a].connectTo(nodes[e.b])
  let wireMs = (getMonoTime() - tw).inMicroseconds.float / 1000.0

  # Let the mesh graft. Heartbeat is 1s.
  await sleepAsync(chronos.seconds(8))
  let meshes = nodes.mapIt(it.meshSize(Topic))

  let probe = newLagProbe()
  probe.start()
  let cpu0 = cpuTime()
  let tp = getMonoTime()

  var r = initRand(seed)
  for k in 0 ..< msgCount:
    let publisher = nodes[r.rand(n - 1)]
    let payload = encodeHeader(uint32(k), nowNs(), payloadBytes)
    discard await publisher.relay.publish(
      Topic, WakuMessage(payload: payload, contentTopic: "/sim/1/t/proto"))
    await sleepAsync(chronos.milliseconds(intervalMs))

  await sleepAsync(chronos.seconds(drainSec))   # drain
  let runMs = (getMonoTime() - tp).inMicroseconds.float / 1000.0
  let cpuMs = (cpuTime() - cpu0) * 1000.0
  probe.stop()

  let totalDelivered = recvCount.foldl(a + b, 0)
  let ideal = n * msgCount
  echo &"  setup     : {setupMs:9.0f} ms   ({setupMs/n.float:6.3f} ms/node)"
  echo &"  wire      : {wireMs:9.0f} ms   ({wireMs/edges.len.float:6.3f} ms/edge, {edges.len} edges)"
  echo &"  degree    : min={dmin} max={dmax} avg={davg:.2f}"
  echo &"  mesh      : min={meshes.min} max={meshes.max} avg={meshes.foldl(a+b,0).float/n.float:.2f}"
  echo &"  delivery  : {totalDelivered}/{ideal} = {100.0*totalDelivered.float/ideal.float:.3f}%"
  if latencies.len > 0:
    echo &"  latency   : p50={percentile(latencies,0.50):.1f} p95={percentile(latencies,0.95):.1f} " &
         &"p99={percentile(latencies,0.99):.1f} max={latencies.max:.1f} ms"
  echo &"  lag       : p50={percentile(probe.samples,0.50):.2f} p99={percentile(probe.samples,0.99):.2f} " &
       &"max={(if probe.samples.len>0: probe.samples.max else: 0.0):.2f} ms  (n={probe.samples.len})"
  echo &"  cpu       : {cpuMs:.0f} ms over {runMs:.0f} ms wall = {100.0*cpuMs/runMs:.1f}% of one core"

  await allFutures(nodes.mapIt(it.stop()))
  simReset()

when isMainModule:
  import std/[os, strutils]
  let
    n         = if paramCount() >= 1: parseInt(paramStr(1)) else: 1000
    degree    = if paramCount() >= 2: parseInt(paramStr(2)) else: 12
    msgCount  = if paramCount() >= 3: parseInt(paramStr(3)) else: 30
    intervalMs= if paramCount() >= 4: parseInt(paramStr(4)) else: 1000
    payload   = if paramCount() >= 5: parseInt(paramStr(5)) else: 1024
    drainSec  = if paramCount() >= 6: parseInt(paramStr(6)) else: 5
  waitFor run(n, degree, msgCount, intervalMs, payload, drainSec, seed = 42)
