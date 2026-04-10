# logos-delivery-simulator

A self-contained protocol simulator for [logos-delivery](https://github.com/logos-messaging/logos-delivery) — the Nim implementation of a libp2p protocol suite for private, censorship-resistant peer-to-peer messaging.

On `docker-compose up`, the simulator orchestrates a network of `logos-delivery` nodes inside Docker (default 5, upper bound around 200), launches a private Anvil blockchain, deploys an RLN contract, registers an RLN membership for every node, and brings up a Grafana + Prometheus + cAdvisor + Epirus block-explorer stack pre-wired to the network. The whole thing runs on an isolated Docker bridge with cluster id `66`, so it cannot accidentally talk to any production fleet.

📖 Full tutorials live in **[The Logos Delivery Simulator Book](https://logos-messaging.github.io/logos-delivery-simulator/)**.

## Prerequisites

- `docker` and `docker-compose` v2 (tested with v2.28.1; v1 is **not** supported)
- Linux or macOS host with at least a few GB of free RAM (scales with `NUM_LD_NODES`)

## Quickstart

```bash
git clone https://github.com/logos-messaging/logos-delivery-simulator.git
cd logos-delivery-simulator
```

Configure the simulation. Either `export` the variables in your shell or drop them in a local `.env` file (gitignored) — `docker-compose` picks `.env` up automatically.

```bash
# Image & network size
export LD_IMAGE=wakuorg/nwaku:latest
export NUM_LD_NODES=5

# Traffic injector (rest-traffic service)
export TRAFFIC_DELAY_SECONDS=15
export MSG_SIZE_KBYTES=10

# RLNv2 limits
export RLN_RELAY_EPOCH_SEC=10
export RLN_RELAY_MSG_LIMIT=2
export MAX_MESSAGE_LIMIT=100   # contract-side cap; must be >= RLN_RELAY_MSG_LIMIT

# Foundry / contract deployment
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ETH_FROM=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
```

Bring everything up:

```bash
docker-compose up -d
```

After a couple of minutes the stack is ready. Open:

| URL | What it is |
|---|---|
| <http://localhost:3000> | Block explorer (Epirus, fronted by nginx) |
| <http://localhost:3001> | Grafana — pre-wired dashboards for the simulated network |
| <http://localhost:8645> | REST API of the bootstrap node (each `nwaku_N` container also exposes its own) |

To follow logs from a specific node:

```bash
# Stream all nwaku replicas merged
docker-compose logs -f nwaku

# Or a specific replica (index = the N in logos-delivery-simulator_nwaku_N)
docker-compose logs -f --index=1 nwaku
```

## What you can do with it

Each tutorial in the book targets one libp2p protocol implemented in `logos-delivery`:

| Tutorial | Protocol exercised |
|---|---|
| [Inject traffic](https://logos-messaging.github.io/logos-delivery-simulator/inject-traffic.html) | Relay (gossipsub) + REST publish |
| [Connect external full node](https://logos-messaging.github.io/logos-delivery-simulator/connect-full-node.html) | Relay + RLN membership |
| [Connect external spam node](https://logos-messaging.github.io/logos-delivery-simulator/connect-spam-node.html) | RLN spam protection + peer scoring |
| [Connect external light node](https://logos-messaging.github.io/logos-delivery-simulator/connect-light-node.html) | Lightpush + RLN proofs from contract |
| [Connect external store node](https://logos-messaging.github.io/logos-delivery-simulator/connect-store-node.html) | Store (historical message retrieval) |
| [Register memberships](https://logos-messaging.github.io/logos-delivery-simulator/register-memberships.html) | RLN membership registration on the contract |

## A note on naming

`logos-delivery` was previously called **nwaku**, and Logos Messaging is a rebrand of the Waku project. Legacy names are still in flight upstream — the binary is `wakunode2`, the Docker image is published as `wakuorg/nwaku`, the Docker Compose service is named `nwaku`, and module paths under `logos-delivery/waku/...` keep the old prefix. These all refer to the same thing. This repo's own variables (`LD_IMAGE`, `NUM_LD_NODES`) and docs use the new naming.

## Troubleshooting

If your kernel ARP table overflows (common with `NUM_LD_NODES` > ~50):

```bash
sysctl net.ipv4.neigh.default.gc_thresh3=32000
```

# Infrastructure

An instance of this service is deployed at https://simulator.waku.org/.

It is configured using the [`wakusim.env`](./wakusim.env) file, and new changes to this repository are picked up using a [GitHub webhook handler](https://github.com/status-im/infra-role-github-webhook). The docker images used are updated using [Watchtower](https://github.com/containrrr/watchtower) as well.

For details on how it works please read the [Ansible role readme file](https://github.com/status-im/infra-misc/blob/master/ansible/roles/waku-simulator/). The original deployment issue can be found [here](https://github.com/status-im/infra-nim-waku/issues/79).

The deployed branch is [deploy-wakusim](https://github.com/logos-messaging/logos-delivery-simulator/tree/deploy-wakusim).

## License

Dual-licensed under [Apache 2.0](./LICENSE-APACHE) and [MIT](./LICENSE-MIT).
