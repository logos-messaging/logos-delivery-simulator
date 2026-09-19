## Tier 2 -- full LogosDelivery stack (kernel / messaging / channels) in one
## process, over real loopback TCP.
##
## Different tier from the relay simulator on purpose:
##   * `WakuNodeBuilder.build()` constructs the switch itself via `newWakuSwitch`
##     (builder.nim:191) with no injection point, and that hardcodes TCP
##     (waku_switch.nim:129) -- so SimTransport cannot reach these layers.
##   * messaging/channels open a persistency job, and every job spawns an OS
##     thread (backend_thread.nim:245), even for `:memory:`.
## Both cap this tier in the hundreds, which matches its actual target: the
## roadmap's channels goal is "up to 201 users in a group chat".
##
## Nodes are constructed SEQUENTIALLY: the broker context is a thread-global
## captured during the async `LogosDelivery.new`, so concurrent construction
## would clobber it mid-flight.

import std/[strformat, sequtils, monotimes, times, os, osproc, strutils]
import chronos, results
import brokers/broker_context
import logos_delivery
import logos_delivery/api/conf/logos_delivery_conf
import logos_delivery/waku/waku_core
import logos_delivery/waku/persistency/persistency
import logos_delivery/messaging/messaging_client_lifecycle
import logos_delivery/channels/reliable_channel_manager
import tests/testlib/wakunodeconf

proc rssMb(): float =
  ## Read our own RSS via ps; cheap enough at the 25-node reporting interval.
  try:
    let (outp, rc) = execCmdEx("ps -o rss= -p " & $getCurrentProcessId())
    if rc == 0: parseFloat(outp.strip()) / 1024.0 else: 0.0
  except CatchableError:
    0.0

proc countThreads(): int =
  ## Thread-per-node is the tier's scaling limit, so track it directly.
  try:
    let (outp, rc) = execCmdEx("ps -M -p " & $getCurrentProcessId() & " | wc -l")
    if rc == 0: parseInt(outp.strip()) - 1 else: 0
  except CatchableError:
    0

proc run(n: int, layer: EntryLayer, dropPersistency: bool) {.async.} =
  var nodes: seq[LogosDelivery]
  echo &"=== N={n} entryLayer={layer} ==="

  let t0 = getMonoTime()
  for i in 0 ..< n:
    # Fresh broker bucket per node; NOT lockNewGlobalBrokerContext, which
    # restores the previous context on scope exit.
    setThreadBrokerContext(NewBrokerContext())
    let conf = defaultTestWakuNodeConf(entryLayer = layer)
    let node = (await LogosDelivery.new(conf)).valueOr:
      echo &"  FAILED constructing node {i}: {error}"
      quit(1)

    # Start the layers individually rather than via LogosDelivery.start(), so the
    # persistency provider can be dropped between the kernel and the layers above
    # it. Every openJob spawns an OS thread (backend_thread.nim:245) even for
    # ":memory:", and messaging + channels open one each -- 2 threads per node.
    # With no provider installed, both take their documented memory-only path
    # ("SDS persistence disabled, running memory-only ... e.g. unit tests") and
    # spawn none. Same call closePersistency() makes internally (waku.nim:364).
    (await node.waku.start()).isOkOr:
      echo &"  FAILED starting kernel {i}: {error}"
      quit(1)
    if dropPersistency:
      GetPersistency.clearProvider(node.waku.brokerCtx)
    if not node.messagingClient.isNil():
      messaging_client_lifecycle.start(node.messagingClient).isOkOr:
        echo &"  FAILED starting messaging {i}: {error}"
        quit(1)
    if not node.reliableChannelManager.isNil():
      reliable_channel_manager.start(node.reliableChannelManager).isOkOr:
        echo &"  FAILED starting channels {i}: {error}"
        quit(1)
    nodes.add(node)
    if (i + 1) mod 25 == 0:
      let el = times.inMilliseconds(getMonoTime() - t0).float / 1000.0
      echo &"  {i+1:5} nodes  {el:7.1f}s  rss={rssMb():7.0f} MB  threads={countThreads()}"

  let buildMs = times.inMilliseconds(getMonoTime() - t0).float
  echo &"  built {n} nodes in {buildMs/1000.0:.1f}s ({buildMs/n.float:.1f} ms/node)"
  echo &"  rss={rssMb():.0f} MB  threads={countThreads()}"
  echo &"  layers: waku={not nodes[0].waku.isNil} " &
       &"messaging={not nodes[0].messagingClient.isNil} " &
       &"channels={not nodes[0].reliableChannelManager.isNil}"

  for node in nodes:
    (await node.stop()).isOkOr:
      discard

when isMainModule:
  let
    n = if paramCount() >= 1: parseInt(paramStr(1)) else: 10
    layer =
      if paramCount() >= 2:
        case paramStr(2)
        of "kernel": EntryLayer.kernel
        of "messaging": EntryLayer.messaging
        else: EntryLayer.channels
      else: EntryLayer.channels
    drop = if paramCount() >= 3: paramStr(3) != "keep-persistency" else: true
  waitFor run(n, layer, drop)
