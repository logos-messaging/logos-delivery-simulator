# Deploy a delivery network

The network can be deployed in a few commands, and requires `docker` and `docker compose`. Some of the configuration is exposed via env flags, but if you are missing some, PRs are accepted.

Some of the most important parameters are:

- `NWAKU_IMAGE` Docker image of nwaku that all nodes will run
- `NUM_NWAKU_NODES` Amount of nwaku nodes
- `RLN_RELAY_EPOCH_SEC` and `RLN_RELAY_MSG_LIMIT` configure the RLNv2 parameter, specifying the amount of messages that are allowed per unit of time.
- `TRAFFIC_DELAY_SECONDS` and `MSG_SIZE_KBYTES` are used to inject traffic via the rest API into the network.

```bash
export NWAKU_IMAGE=quay.io/wakuorg/nwaku-pr:2759-rln-v2
export NUM_NWAKU_NODES=5
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
docker logs logos-delivery-simulator_nwaku_1
docker logs logos-delivery-simulator_nwaku_2
```

Or if you want to follow the logs

```bash
docker logs logos-delivery-simulator_nwaku_1 --follow
```

Once the network of nwaku nodes is up and running we can use it to perform different tests, connecting other nodes that we fully control with some specific characteristics. This ranges from connecting spammer nodes, light clients, and in the future unsynced nodes, etc.


Now that we have the network deployed we can use it. Hereunder we describe how to use the network deployed by `logos-delivery-simulator` to perform end-to-end tests of any desired feature. We focus on the following ones:

- Inject traffic:
- Connect external full node:
- Connect external spammer node:
- Connect external light node:
- Register memberships:

⚠️ For every use case, ensure that your node is configured in the same way as the rest of the nodes, otherwise messages may be lost. Note that it can be also an intended test, seeing how the network reacts to other nodes connecting to it.