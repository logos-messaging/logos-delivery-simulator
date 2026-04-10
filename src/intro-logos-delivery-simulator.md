# Introduction to Logos Delivery Simulator

The [logos-delivery-simulator](https://github.com/logos-messaging/logos-delivery-simulator) is a **protocol simulator** for [logos-delivery](https://github.com/logos-messaging/logos-delivery) — the Nim implementation of a libp2p protocol suite for private, censorship-resistant peer-to-peer messaging.

## What it does

The simulator orchestrates a network of `logos-delivery` nodes inside Docker, on a single machine, so you can exercise the protocol stack end-to-end without depending on any public network. Concretely, on `docker-compose up` it:

- spins up a configurable number of `logos-delivery` nodes (default: 5, upper bound around 200) all connected through a single bootstrap node via discv5,
- launches a private Anvil blockchain ([foundry](https://github.com/foundry-rs/foundry)) under your full control,
- deploys an RLN (Rate Limiting Nullifier) contract on that chain and registers an RLN membership for every node so they can publish valid rate-limited messages,
- exposes each node's REST API so you can inject traffic, query the store, attach external nodes, etc.,
- ships a Grafana + Prometheus + cAdvisor + Epirus block-explorer stack pre-wired to the simulated network for observability.

The whole network runs on an isolated Docker bridge (`logos-delivery-simulator_simulation`) and uses an ad-hoc cluster id (`66`) so it cannot accidentally talk to any production fleet.

## What protocols you can exercise

The tutorials in this book each target one of the libp2p protocols implemented in `logos-delivery`:

| Tutorial | Protocol exercised |
|---|---|
| [Inject traffic](./inject-traffic.md) | Relay (gossipsub) + REST publish |
| [Connect external full node](./connect-full-node.md) | Relay + RLN membership |
| [Connect external spam node](./connect-spam-node.md) | RLN spam protection + peer scoring |
| [Connect external light node](./connect-light-node.md) | Lightpush + RLN proofs from contract |
| [Connect external store node](./connect-store-node.md) | Store (historical message retrieval) |
| [Register memberships](./register-memberships.md) | RLN membership registration on the contract |

A full list of the protocols implemented by `logos-delivery` (Relay, Store, Filter, Lightpush, Peer Exchange, RLN Relay, Metadata, Mix, Rendezvous) is in [logos-delivery/AGENTS.md](https://github.com/logos-messaging/logos-delivery/blob/master/AGENTS.md). The specifications themselves live at [rfc.vac.dev/waku](https://rfc.vac.dev/waku) under the `WAKU2-XXX` identifiers.

## Goals

- Test new protocol features end-to-end with multiple nodes before they go to a real fleet.
- Run as a long-lived network on `master` to catch breaking changes early.
- Explore the protocol's limits under different loads, message sizes, and rate limits.
- Provide a controlled, easily-reproducible environment for debugging.

## A note on naming

`logos-delivery` was previously called **nwaku**, and [Logos Messaging](https://github.com/logos-messaging) is a rebrand of the [Waku](https://waku.org) project. A lot of legacy names are still in flight and you'll see them in this repo and the upstream — they all refer to the same thing:

- The compiled binary is still called `wakunode2` (`logos-delivery/Makefile`).
- The shared library is `liblogosdelivery`.
- The published Docker image used by `${LD_IMAGE}` is still pushed to `quay.io/wakuorg/nwaku-pr:<tag>` (`logos-delivery/.github/workflows/container-image.yml:91`).
- The default fallback in `docker-compose.yml` is `wakuorg/nwaku:latest`.
- Specifications still live under the `WAKU2-XXX` namespace at `rfc.vac.dev/waku`.
- Inside the source tree of `logos-delivery`, modules are still named `waku/waku_relay`, `waku/waku_store`, etc.

This is consistent with the upstream project's stance, quoted from `logos-delivery/AGENTS.md`: *"Logos Messaging was formerly known as Waku. Waku-related terminology remains within the codebase for historical reasons."*

You don't need to do anything about it — it's just useful to know that `nwaku`, `wakunode2`, and `logos-delivery` all refer to the same binary in this repo.
