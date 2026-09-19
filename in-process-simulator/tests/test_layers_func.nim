## Does the messaging layer actually WORK with persistency dropped?
## m4 shows the layers instantiate and cost ~1 thread total; this checks that
## two such nodes can connect over real TCP and move a message end to end.
## "Starts" is not "works" -- without this, the m4 numbers mean nothing.

import std/[strformat, sequtils, options, strutils]
import stew/byteutils
import chronos, results
import brokers/broker_context
import logos_delivery
import logos_delivery/api/conf/logos_delivery_conf
import logos_delivery/waku/waku_core
import libp2p/switch
import logos_delivery/waku/node/peer_manager
import logos_delivery/waku/node/waku_node
import logos_delivery/waku/persistency/persistency
import logos_delivery/messaging/messaging_client_lifecycle
import logos_delivery/messaging/messaging_client
import logos_delivery/channels/reliable_channel_manager
import logos_delivery/waku/factory/app_callbacks
import tests/testlib/wakunodeconf

var gReceived {.threadvar.}: seq[string]

proc mkNode(dropPersistency: bool, observe: bool): Future[LogosDelivery] {.async.} =
  setThreadBrokerContext(NewBrokerContext())
  let conf = defaultTestWakuNodeConf(entryLayer = EntryLayer.channels)
  var cbs: AppCallbacks = nil
  if observe:
    # Observe at the relay layer: proves the payload actually crossed the wire
    # into this node, rather than just that send() returned ok.
    var h: WakuRelayHandler
    h = proc(t: PubsubTopic, msg: WakuMessage): Future[void] {.async, gcsafe.} =
      gReceived.add(string.fromBytes(msg.payload))
    cbs = AppCallbacks(relayHandler: h)
  let node = (await LogosDelivery.new(conf, cbs)).valueOr:
    raiseAssert "new: " & error
  (await node.waku.start()).isOkOr:
    raiseAssert "kernel start: " & error
  if dropPersistency:
    GetPersistency.clearProvider(node.waku.brokerCtx)
  if not node.messagingClient.isNil():
    messaging_client_lifecycle.start(node.messagingClient).isOkOr:
      raiseAssert "messaging start: " & error
  if not node.reliableChannelManager.isNil():
    reliable_channel_manager.start(node.reliableChannelManager).isOkOr:
      raiseAssert "channels start: " & error
  return node

proc run(dropPersistency: bool) {.async.} =
  echo &"=== persistency dropped={dropPersistency} ==="
  gReceived = @[]
  let a = await mkNode(dropPersistency, observe = false)
  let b = await mkNode(dropPersistency, observe = true)

  echo "  A listen: ", a.waku.node.announcedAddresses.mapIt($it)
  echo "  B listen: ", b.waku.node.announcedAddresses.mapIt($it)

  let bInfo = b.waku.node.switch.peerInfo.toRemotePeerInfo()
  await waku_node.connectToNodes(a.waku.node, @[bInfo])
  echo "  connected"

  let topic = ContentTopic("/sim/1/layer-test/proto")
  (await b.messagingClient.subscribe(topic)).isOkOr:
    raiseAssert "subscribe: " & error
  (await a.messagingClient.subscribe(topic)).isOkOr:
    raiseAssert "subscribe A: " & error
  await sleepAsync(chronos.seconds(3))

  let envelope = MessageEnvelope.init(topic, "hello-through-the-layers")
  let reqId = (await a.messagingClient.send(envelope)).valueOr:
    raiseAssert "send: " & error
  echo "  sent, requestId=", reqId
  await sleepAsync(chronos.seconds(3))
  echo "  B relay-observed payloads: ", gReceived
  if gReceived.anyIt(it.contains("hello-through-the-layers")):
    echo "  LAYER-FUNC PASS"
  else:
    echo "  LAYER-FUNC FAIL (nothing arrived at B)"

  (await a.stop()).isOkOr: discard
  (await b.stop()).isOkOr: discard

when isMainModule:
  import std/os
  let drop = if paramCount() >= 1: paramStr(1) != "keep" else: true
  waitFor run(drop)
