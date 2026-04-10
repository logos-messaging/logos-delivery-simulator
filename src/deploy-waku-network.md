# Deploy a Logos Delivery network

This page deploys a self-contained network of [logos-delivery](https://github.com/logos-messaging/logos-delivery) nodes (the `wakunode2` binary, distributed as a Docker image) on a single machine. It requires `docker` and `docker-compose`. Configuration is exposed through environment variables — if a knob you need is missing, PRs are welcome.

The most important parameters are:

- `LD_IMAGE` — the `logos-delivery` Docker image that every node will run. The image is still published under the legacy `wakuorg/nwaku` namespace (see [the upstream container build](https://github.com/logos-messaging/logos-delivery/blob/master/.github/workflows/container-image.yml)); pin a tag for reproducible runs.
- `NUM_LD_NODES` — number of `logos-delivery` nodes to launch (default 5; upper bound around 200 depending on host resources).
- `RLN_RELAY_EPOCH_SEC` and `RLN_RELAY_MSG_LIMIT` — RLNv2 parameters that cap how many messages each node may publish per epoch.
- `TRAFFIC_DELAY_SECONDS` and `MSG_SIZE_KBYTES` — used by the bundled `rest-traffic` injector to drive load through each node's REST API.

```bash
export LD_IMAGE=wakuorg/nwaku:latest
export NUM_LD_NODES=5
export RLN_RELAY_EPOCH_SEC=1
export RLN_RELAY_MSG_LIMIT=1

export TRAFFIC_DELAY_SECONDS=15
export MSG_SIZE_KBYTES=10

export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ETH_FROM=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
```

Once configured, start all containers:

```bash
docker-compose --compatibility up -d
```

After a couple of minutes, everything should be running at:

- `http://localhost:3000` Block explorer
- `http://localhost:3001` Grafana metrics

For greater observability, one can access each node logs as follows:

```bash
# All nwaku replicas at once
docker-compose logs nwaku

# A specific replica (e.g. index 1 or 2)
docker-compose logs --index=1 nwaku
docker-compose logs --index=2 nwaku
```

Or if you want to follow the logs

```bash
docker-compose logs -f --index=1 nwaku
```

Once the network of `logos-delivery` nodes is up and running we can use it to perform different tests, connecting other nodes that we fully control with specific characteristics. This ranges from connecting spammer nodes, light clients, store nodes, and in the future unsynced nodes, etc.


Now that we have the network deployed we can use it. Hereunder we describe how to use the network deployed by `logos-delivery-simulator` to perform end-to-end tests of any desired feature. Each tutorial below targets a specific protocol from the [logos-delivery](https://github.com/logos-messaging/logos-delivery) suite:

- Inject traffic:
- Connect external full node:
- Connect external spammer node:
- Connect external light node:
- Register memberships:

⚠️ For every use case, ensure that your node is configured in the same way as the rest of the nodes, otherwise messages may be lost. Note that it can be also an intended test, seeing how the network reacts to other nodes connecting to it.