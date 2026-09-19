## M1a -- two real WakuRelay nodes in one process, over libp2p's stock in-memory
## transport. Deliberately the smallest thing that can work: it isolates "does
## WakuRelay run on a switch we built ourselves, with a per-node broker context"
## from "does our own SimTransport work". M1b swaps the transport underneath.

import std/[strformat, sequtils, tables, sets]
import stew/byteutils
import chronos, results
import libp2p/[builders, switch, multiaddress, peerid, peerinfo]
import libp2p/protocols/protocol
import libp2p/crypto/crypto as libp2p_crypto
import brokers/broker_context
import sim/transport/sim_transport
import logos_delivery/waku/waku_relay
# protocolMatcher lives in the peer manager; use the real one so codec matching
# is identical to a production node (prefix match, tolerating version suffixes).
import logos_delivery/waku/node/peer_manager
import logos_delivery/waku/waku_core

const
  TestTopic = "/waku/2/rs/2/0"
  MaxMsgSize = 150 * 1024

type SimNode = ref object
  idx: int
  switch: Switch
  relay: WakuRelay
  received: seq[string]

proc memAddr(idx: int): MultiAddress =
  simAddress(&"n{idx}")

proc newSimNode(idx: int, rng: libp2p_crypto.Rng): SimNode =
  # Each node gets its own broker bucket. WakuRelay captures the *thread*-global
  # context at construction (protocol.nim:381), so setting it here is enough --
  # no change to logos-delivery required. Without this, all nodes' WakuPeerEvent
  # listeners would fire for every other node's peer events.
  setThreadBrokerContext(NewBrokerContext())

  let switch = SwitchBuilder
    .new()
    .withRng(rng)
    .withAddress(memAddr(idx))
    .withSimTransport()
    .withYamux()
    .withNoise()
    .withMaxConnections(32)
    .withPeerStore(48)
    .build()

  let relay = WakuRelay.new(switch, MaxMsgSize).valueOr:
    raise newException(CatchableError, "WakuRelay.new failed: " & $error)

  switch.mount(relay, protocolMatcher(WakuRelayCodec))
  return SimNode(idx: idx, switch: switch, relay: relay)

proc start(n: SimNode) {.async.} =
  # switch.start() -> ms.start() already starts every mounted protocol, so the
  # relay must NOT be started again here: a second GossipSub.start logs
  # "Starting gossipsub twice" and spawns a duplicate send task per peer.
  await n.switch.start()

proc subscribe(n: SimNode) =
  let node = n
  var onMessage: WakuRelayHandler
  onMessage = proc(topic: PubsubTopic, msg: WakuMessage): Future[void] {.async, gcsafe.} =
    node.received.add(byteutils.fromBytes(string, msg.payload))
  n.relay.subscribe(TestTopic, onMessage)

proc main() {.async.} =
  let rng = libp2p_crypto.newRng()
  let a = newSimNode(0, rng)
  let b = newSimNode(1, rng)

  await allFutures(a.start(), b.start())
  a.subscribe()
  b.subscribe()

  echo "A addrs: ", a.switch.peerInfo.listenAddrs.mapIt($it)
  echo "B addrs: ", b.switch.peerInfo.listenAddrs.mapIt($it)

  await a.switch.connect(b.switch.peerInfo.peerId, @[memAddr(1)])
  echo "connected; A conns=", a.switch.connManager.connCount(b.switch.peerInfo.peerId)

  # Let the gossipsub graft settle before publishing.
  await sleepAsync(2.seconds)
  echo "A mesh peers on topic: ", a.relay.mesh.getOrDefault(TestTopic).len
  echo "B mesh peers on topic: ", b.relay.mesh.getOrDefault(TestTopic).len

  let msg = WakuMessage(
    payload: toBytes("hello-from-A"), contentTopic: "/sim/1/test/proto")
  let res = await a.relay.publish(TestTopic, msg)
  echo "publish result: ", res

  await sleepAsync(2.seconds)
  echo "A received: ", a.received
  echo "B received: ", b.received

  if b.received.len == 1 and b.received[0] == "hello-from-A":
    echo "M1a PASS"
  else:
    echo "M1a FAIL"; quit(1)

waitFor main()
