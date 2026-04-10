# logos-delivery-simulator

Check 📖 [The Logos Delivery Simulator Book](https://logos-messaging.github.io/logos-delivery-simulator/)📖

## Quickstart

```
git clone https://github.com/logos-messaging/logos-delivery-simulator.git
cd logos-delivery-simulator
```

Configure the simulation parameters. You can place the env variable in an `.env` file.

```
export NWAKU_IMAGE=quay.io/wakuorg/nwaku-pr:2759-rln-v2
export NUM_NWAKU_NODES=5
export TRAFFIC_DELAY_SECONDS=15
export MSG_SIZE_KBYTES=10
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ETH_FROM=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
export RLN_RELAY_EPOCH_SEC=10
export RLN_RELAY_MSG_LIMIT=2
export MAX_MESSAGE_LIMIT=100  # Contract's message limit. Needs to be higher or equal than RLN_RELAY_MSG_LIMIT, otherwise nodes won't start correctly.
```

Run the following command
```
docker compose up -d
```
(tested with Docker Compose version v2.28.1. Notice that we don't support docker compose v1)

## Warning

In case arp tables are overflowing:

  ```
  sysctl net.ipv4.neigh.default.gc_thresh3=32000
  ```

# Infrastructure

An instance of this service is deployed at https://simulator.waku.org/.

It is configured using [`wakusim.env`](./wakusim.env) file, and new changes to this repository are picked up using a [GitHub webhook handler](https://github.com/status-im/infra-role-github-webhook).
The docker images used are updated using [Watchtower](https://github.com/containrrr/watchtower) as well.

For details on how it works please read the [Ansible role readme file](https://github.com/status-im/infra-misc/blob/master/ansible/roles/waku-simulator/). The original deployment issue can be found [here](https://github.com/status-im/infra-nim-waku/issues/79).

The deployed branch is [deploy-wakusim](https://github.com/logos-messaging/logos-delivery-simulator/tree/deploy-wakusim).
