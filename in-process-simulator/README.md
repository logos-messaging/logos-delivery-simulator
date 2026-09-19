# In-process simulator

Runs many **real** logos-delivery nodes inside a single process, so scale
experiments that otherwise need the Vac-DST Kubernetes cluster can run on a
laptop in minutes.

Complementary to the docker-compose simulator in the root of this repo, not a
replacement:

|  | docker-compose sim (repo root) | in-process sim (here) |
|---|---|---|
| node = | a container | an object in one process |
| ceiling | ~200 (the `/24` subnet, 520 anvil accounts, 200 hardcoded Prometheus targets) | 3000 relay / ~200 full-stack |
| RLN, real deployment | yes | no |
| per-node OS/resource cost | real | not reproducible |
| iteration | minutes to bring up | seconds |

Use this to catch protocol regressions fast; use the compose stack and the
cluster to validate a *deployed node*.

## Build

Needs a logos-delivery checkout that has been built at least once (it reads
`nimble.paths` from it, so the code under test is exactly what that checkout
builds). `nim.cfg` is generated and not committed.

```sh
make LD_ROOT=~/src/logos-delivery test     # correctness checks, they assert
make LD_ROOT=~/src/logos-delivery bench    # measurement, prints numbers
```

## Two tiers

The two tiers exist because they cannot share a transport, and because the
layers have genuinely different scale targets: the relay experiment is 3000
nodes (10ksim's `nodes_3k.yaml`), while the roadmap's channels goal is "up to
201 users in a group chat" (`2026-chat-beta.md:93`).

|  | Tier 1 — relay / gossipsub | Tier 2 — kernel / messaging / channels |
|---|---|---|
| scale reached | 3000 nodes | 200 nodes |
| transport | `SimTransport`, in-memory | real TCP |
| stack | `Switch` + `WakuRelay` | full `LogosDelivery` |
| threads | 0 extra | 0 extra (see persistency) |
| logos-delivery changes | **none** | **none** |

Tier 2 cannot use `SimTransport`: `WakuNodeBuilder.build()` constructs the switch
itself via `newWakuSwitch` (`builder.nim:191`) with no injection point, and that
hardcodes TCP (`waku_switch.nim:129`).

## Tier 1 — relay at 3000 nodes

`tests/bench_relay_scale.nim`. Measured on an M5 (10 cores, 32 GB), 1 KB
messages at 1 msg/s, random k-regular topology:

| N | degree | delivery | CPU | RSS |
|---|---|---|---|---|
| 500 | 12 | 100% | 16% of one core | — |
| 1000 | 12 | 100% | 41% of one core | — |
| 3000 | 12 | **100%** | ~97% (publish phase) | 3.3 GB |
| 3000 | 30 | 90%* | ~100% | 5.8 GB |

\* the degree-30 row used too short a drain window; see "Pitfalls".

Node construction is ~0.35 ms/node. Wiring is **crypto-bound**, not I/O-bound:
~2.7 ms/edge is the Noise XX handshake on the single chronos thread, so 3000
nodes at degree 30 (44,802 edges) takes ~2 minutes to wire. Wire once and run
several scenarios against it; keep wiring out of the measurement window.

### Why ORC

logos-delivery mandates `--mm:refc` for its own binaries. This harness builds
with `--mm:orc`, and it is the difference between working and not:

| N=1000, degree 12 | refc | ORC |
|---|---|---|
| CPU | 99.9% of a core | **41%** |
| delivery | 64.9% | **100%** |
| latency p50 | 26.7 s | **121 ms** |

`sample` showed **90% of all CPU in `nimGCunref`** — refc churning reference
counts on chronos future continuations, cost growing with heap size and so with
N. Only ~10% was protocol work. Under refc the relay tier saturates at ~500
nodes.

This is a deliberate fidelity trade: ORC changes destruction timing, so the
harness is not exercising the allocator production uses. Acceptable while the
scope is mesh behaviour and dissemination; it belongs in the ledger below.

## Tier 2 — validating the layers

`tests/test_layers_func.nim` (asserts) and `tests/bench_layers.nim` (measures).

### Disabling persistency

Every `openJob` spawns an OS thread (`backend_thread.nim:245`) — **even for
`:memory:`**, since `startStorageThread` is called unconditionally. Two call
sites, so a channels node costs threads per node:

* `messaging/messaging_client_lifecycle.nim:24` — `MessagingJobId`
* `channels/api/channel_lifecycle.nim:26` — `SdsJobId`

Both already **degrade gracefully** with no provider installed; the SDS one
documents it as the unit-test path ("memory-only fallback when no provider is
installed (e.g. unit tests)"). The only obstacle is that `waku.start()`
unconditionally registers the provider (`waku.nim:385`).

Starting the layers individually lets us drop it in between — the same call
`closePersistency()` makes internally (`waku.nim:364`), all parts public:

```nim
setThreadBrokerContext(NewBrokerContext())            # per-node broker bucket
let node = (await LogosDelivery.new(conf)).tryGet()
(await node.waku.start()).tryGet()                    # registers the provider
GetPersistency.clearProvider(node.waku.brokerCtx)     # drop it
messaging_client_lifecycle.start(node.messagingClient).tryGet()
reliable_channel_manager.start(node.reliableChannelManager).tryGet()
```

| channels layer, full stack | threads | RSS | build |
|---|---|---|---|
| 10 nodes, persistency kept | 11 | 83 MB | 2.1 ms/node |
| 10 nodes, dropped | **1** | 17 MB | 1.0 ms/node |
| **200 nodes, dropped** | **1** | **99 MB** | 0.9 ms/node |

**What it costs:** the layers become *memory-only*, not disabled. Reliable-channel
sync, delivery and dedup still run and are testable. What is lost is
**durability** — restart recovery and backfill from persisted history. A node
restarted mid-run returns with nothing: faithful to an OOM-killed pod, not to a
graceful restart. Churn tests that need state to survive must keep persistency
and pay one thread per node (fine at ~200).

**Verified functional, not merely started:** `test_layers_func.nim` has two
full-stack nodes bind real TCP, connect, and `messagingClient.send()` reach the
other node's relay handler. Without that check the table above would be
meaningless.

## Finding: yamux deadlocks over libp2p's in-memory transport

`libp2p 2.3.1`'s own `MemoryTransport` cannot carry GossipSub under yamux.
Reproduced with **plain libp2p, no waku involved** (`tests/test_transport_matrix.nim`):

| muxer | transport | result |
|---|---|---|
| yamux | memory | **fails** — `finishUpgrade` errors with `Timeout exceeded!` or `Stream Underlying Connection Closed!`, depending on which side gives up first |
| yamux | tcp | works |
| mplex | memory | works |
| mplex | tcp | works |

`bridgedConnections` builds `BufferStream`s whose `readQueue` has capacity **1**
(`bufferstream.nim:48`), so a write blocks until the peer's read loop consumes
it. Yamux writes in both directions during upgrade before either side reads, and
the ends block on each other. TCP survives only because the kernel socket buffer
absorbs the initial burst.

This matters beyond this harness: logos-delivery offers yamux ahead of mplex
(`waku_switch.nim:88-89`).

`src/sim/transport/sim_transport.nim` replaces it and fixes three further defects:
a single-shot listener whose `dial()` deletes the listener *before* completing
the accept future (`memorymanager.nim:45-47`); a duplicate address that silently
deafens a node for the whole run, because `Switch.accept` swallows the error as
"Exception in accept loop, exiting" (`switch.nim:319-323`); and an unbounded
`connections` leak.

## Pitfalls (each of these cost us a wrong conclusion)

* **Drain window.** Counting deliveries too soon after the last publish reports
  in-flight messages as lost. A 5 s drain at N=3000 (latency p50 ~8 s) showed
  85.7% delivery; a 60 s drain showed **100%**. Scale the drain to observed
  latency.
* **`-d:X=false` still defines X.** `postgres` and `metrics` are gated by bare
  `when defined(X)`, so `-d:metrics=false` *enables* metrics. Omit them.
* **`switch.start()` already starts mounted protocols** via `ms.start()`. Calling
  `relay.start()` too logs "Starting gossipsub twice" and spawns a duplicate send
  task per peer.
* **Construct Tier-2 nodes sequentially.** The broker context is a thread-global
  captured during the async `LogosDelivery.new`, so concurrent construction
  clobbers it. `lockNewGlobalBrokerContext` is unsuitable — it *restores* the
  previous context on scope exit.
* **Logging was not the bottleneck.** Quieting chronicles changed CPU by 0.1
  points. Profile before optimising.

## Fidelity ledger

**Faithful** — real code, scheduler-independent: gossipsub mesh formation and
graft/prune (measured avg degree 6.00 against waku's `D=6`), delivery ratio,
bytes on the wire, waku relay validators and message hashing, messaging/channels
protocol logic, A/B comparison of two builds under identical load.

**Distorted:** absolute latency (no RTT, and it absorbs queueing once the single
dispatcher saturates); per-node memory (shared heap); backpressure (a queue, not
TCP — no congestion window, RTO or bufferbloat); peer scoring paths keyed on IP
never fire on Tier 1; ORC rather than production's refc.

**Not testable here** — keep on the cluster: discv5 discovery and its ~8 KB/s per
node, RLN, real per-node resource cost and OOM/cgroup behaviour, kernel TCP
internals, NAT traversal, per-node Prometheus metrics (the registry is a process
global).

## Status / next steps

Working and measured: Tier 1 to 3000 nodes, Tier 2 to 200 with layers verified
functional.

Not yet done:
* **`src/sim/transport/link.nim` is written but NOT wired into `SimTransport`.**
  It models propagation delay, bandwidth and backpressure via a single global
  delay wheel; it compiles and is unused. Integrating it is the next step, and it
  is what would make Tier 1 latency numbers meaningful.
* Bandwidth counters exist in `SimTransport` (`bytesWritten`) but are not
  reported. Wiring them up is the cheapest way to validate against the published
  ~10.1 KB/s per node at 1000 nodes, since bandwidth stays valid even when the
  dispatcher is saturated.
* Churn (kill a node, restart with a fresh keypair) — pure orchestration, and the
  highest-value impairment for the layers.
* Tier 2 impairments would need OS-level shaping (`dummynet`/`pfctl`), since
  `SimTransport` is not in that path.

## Layout

```
src/sim/node.nim                     Tier 1 node: broker ctx, switch, relay
src/sim/topology.nim                 k-regular / ring generators
src/sim/probes.nim                   dispatcher-lag probe (run-validity gate)
src/sim/transport/sim_transport.nim  in-memory transport
src/sim/transport/link.nim           delay/bandwidth model (NOT yet wired in)
tests/test_transport_matrix.nim      muxer x transport matrix (the yamux bug)
tests/test_relay_two_nodes.nim       2 real WakuRelay nodes
tests/test_layers_func.nim           full stack sends a message end to end
tests/bench_ring.nim                 N-node ring + per-edge timing
tests/bench_relay_scale.nim          the scaling harness
tests/bench_layers.nim               layer scaling + persistency comparison
tools/gen_nim_cfg.sh                 regenerate nim.cfg from $LD_ROOT
```
