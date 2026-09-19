## The simulator's node recipe: a real `WakuRelay` on a switch we build here.
##
## Deliberately NOT `newWakuSwitch` / `WakuNodeBuilder` / `WakuNode`:
##   * `newWakuSwitch` hardcodes `withTcpTransport` (waku_switch.nim:129) and we
##     need our own transport;
##   * `WakuNode` drags in NetConfig, ENR, DnsResolver, the peer manager's
##     background loops and the health monitor, none of which a relay-only
##     gossip experiment needs, and all of which cost per-node memory and timers.
##
## The code under test -- GossipSub and WakuRelay -- is the real thing, linked
## from the logos-delivery checkout. Nothing in logos-delivery is modified.

{.push raises: [].}

import std/[strformat, tables, sets]
import chronos, chronicles, results
import libp2p/[builders, switch, multiaddress, peerid, peerinfo]
import libp2p/crypto/crypto as lpcrypto
import brokers/broker_context
import logos_delivery/waku/waku_relay
import logos_delivery/waku/waku_core
# The real prefix matcher, so codec matching behaves exactly as on a production
# node (tolerates version suffixes like /vac/waku/relay/2.0.0-beta1).
import logos_delivery/waku/node/peer_manager
import ./transport/sim_transport

export sim_transport, waku_relay, waku_core

type SimNode* = ref object
  idx*: int
  switch*: Switch
  relay*: WakuRelay
  onDeliver*: proc(node: SimNode, topic: PubsubTopic, msg: WakuMessage) {.gcsafe, raises: [].}

proc nodeAddr*(idx: int): MultiAddress {.raises: [LPError, ValueError].} =
  simAddress(&"n{idx}")

proc peerId*(n: SimNode): PeerId =
  n.switch.peerInfo.peerId

proc newSimNode*(
    idx: int,
    rng: lpcrypto.Rng,
    maxConnections: int,
    maxMessageSize = int(DefaultMaxWakuMessageSize),
): SimNode {.raises: [LPError, ValueError, CatchableError].} =
  # Each node gets its own broker bucket. WakuRelay captures the *thread*-global
  # broker context at construction (waku_relay/protocol.nim:381), so setting it
  # here is enough -- no change to logos-delivery is needed. Without it every
  # node's WakuPeerEvent listener would fire for every other node's peer events.
  setThreadBrokerContext(NewBrokerContext())

  let switch = SwitchBuilder
    .new()
    .withRng(rng)
    .withAddress(nodeAddr(idx))
    .withSimTransport()
    .withYamux()
    .withNoise()
    .withMaxConnections(maxConnections)
    # Explicit, because the default is maxConnections * 5 (waku_switch.nim:114),
    # which at 3000 nodes is the one genuine per-node memory offender.
    # PeerManager.new asserts capacity >= maxConnections.
    .withPeerStore(maxConnections + 16)
    .build()

  let relay = WakuRelay.new(switch, maxMessageSize).valueOr:
    raise newException(CatchableError, "WakuRelay.new failed: " & $error)

  switch.mount(relay, protocolMatcher(WakuRelayCodec))
  SimNode(idx: idx, switch: switch, relay: relay)

proc start*(n: SimNode) {.async: (raises: [CancelledError, LPError]).} =
  # switch.start() -> ms.start() already starts every mounted protocol. Starting
  # the relay again logs "Starting gossipsub twice" and spawns a duplicate send
  # task per peer, so it must not be started separately.
  await n.switch.start()

proc stop*(n: SimNode) {.async: (raises: [CancelledError]).} =
  await n.switch.stop()

proc subscribe*(n: SimNode, topic: PubsubTopic) =
  let node = n
  var h: WakuRelayHandler
  h = proc(t: PubsubTopic, msg: WakuMessage): Future[void] {.async, gcsafe.} =
    if not node.onDeliver.isNil:
      node.onDeliver(node, t, msg)
  n.relay.subscribe(topic, h)

proc meshSize*(n: SimNode, topic: PubsubTopic): int =
  n.relay.mesh.getOrDefault(topic).len

proc connectTo*(a: SimNode, b: SimNode) {.async: (raises: [CancelledError, DialFailedError, LPError, ValueError]).} =
  ## One directed edge. The sim transport's listener is persistent, so unlike
  ## libp2p's memory transport this needs no retry loop and no per-target lock.
  await a.switch.connect(b.peerId, @[nodeAddr(b.idx)])
