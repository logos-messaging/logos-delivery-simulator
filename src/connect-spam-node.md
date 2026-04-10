# Connect external spam node

> **Protocol exercised:** RLN Relay (spam protection) + gossipsub peer scoring — verifies that nodes exceeding their RLN rate limit are detected and disconnected via peer score.

By using the [nwaku-spammer](https://github.com/waku-org/nwaku/pull/2821) build, you can connect a node to the network that spams the other nodes, sending messages exceeding its rate limit. It will register an RLN membership at startup. It should be configured with the same contract and `rln-relay-user-message-limit` as the rest of the network. If a node spams enough for its gossipsub peer score to drop below the threshold, the other [logos-delivery](https://github.com/logos-messaging/logos-delivery) nodes will disconnect from it.

- ⚠️ change `staticnode` to the node you wish. Note that the multiaddress is logged by every peer at startup.

```bash
docker run -it --network logos-delivery-simulator_simulation quay.io/wakuorg/nwaku-pr:2821 \
      --relay=true \
      --rln-relay=true \
      --rln-relay-dynamic=true \
      --rln-relay-eth-client-address=http://foundry:8545 \
      --rln-relay-eth-contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
      --rln-relay-epoch-sec=1 \
      --rln-relay-user-message-limit=1 \
      --log-level=DEBUG \
      --staticnode=/ip4/10.2.0.16/tcp/60000/p2p/16Uiu2HAmAA99YfoLitSXgY1bHaqjaTKhyrU4M4y3D1rVj1bmcgL8 \
      --pubsub-topic=/waku/2/rs/66/0 \
      --cluster-id=66 \
      --rln-relay-eth-private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
      --rln-relay-cred-path=/keystore.json \
      --rln-relay-cred-password=password123 \
      --spammer=true \
      --spammer-delay-between-msg=200
```

An alternative config for the spamming node is to have it connect to the discv5 network instead of a single static node.
The `staticnode` config can be replaced with the below config. The bootstrap node will log its ENR.

```bash
 --discv5-discovery=true \
 --discv5-enr-auto-update=True \
 --discv5-bootstrap-node=BOOTSTRAP_ENR\
```

You can also try to connect multiple spamming nodes, but it might be necessary to use a different private-key for each one to avoid the limitation of multiple contract transactions with the same nonce. Otherwise add a delay before running a new node. Note the `&`. Remember to kill the new nodes once you are done.

```bash
for i in {1..5}; do
docker run -it --network logos-delivery-simulator_simulation quay.io/wakuorg/nwaku-pr:2821 \
      --relay=true \
      --rln-relay=true \
      --rln-relay-dynamic=true \
      --rln-relay-eth-client-address=http://foundry:8545 \
      --rln-relay-eth-contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
      --rln-relay-epoch-sec=1 \
      --rln-relay-user-message-limit=1 \
      --log-level=DEBUG \
      --staticnode=/ip4/10.2.0.16/tcp/60000/p2p/16Uiu2HAmAA99YfoLitSXgY1bHaqjaTKhyrU4M4y3D1rVj1bmcgL8 \
      --pubsub-topic=/waku/2/rs/66/0 \
      --cluster-id=66 \
      --rln-relay-eth-private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
      --rln-relay-cred-path=/keystore.json \
      --rln-relay-cred-password=password123 \
      --spammer=true \
      --spammer-delay-between-msg=200 &
done
```

The spammer node also provides a method to test burst messaging. It will send the total user-message-limit of messages sequentially without pauses, then rests for the epoch period and repeats.

```bash
docker run -it --network logos-delivery-simulator_simulation quay.io/wakuorg/nwaku-pr:2821 \
      --relay=true \
      --rln-relay=true \
      --rln-relay-dynamic=true \
      --rln-relay-eth-client-address=http://foundry:8545 \
      --rln-relay-eth-contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
      --rln-relay-epoch-sec=1 \
      --rln-relay-user-message-limit=1 \
      --log-level=DEBUG \
      --staticnode=/ip4/10.2.0.16/tcp/60000/p2p/16Uiu2HAmAA99YfoLitSXgY1bHaqjaTKhyrU4M4y3D1rVj1bmcgL8 \
      --pubsub-topic=/waku/2/rs/66/0 \
      --cluster-id=66 \
      --rln-relay-eth-private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
      --rln-relay-cred-path=/keystore.json \
      --rln-relay-cred-password=password123 \
      --spammer=true \
      --spammer-burst=true
```

🎯**Goals**:

- Connect a spamming node(s) to the network where spam messages are rejected and misbehaving peers are disconnected for a time.
- See how the network reacts to different spamming rates.

👀**Observability**:

- Check the logs of the new node logs, ensuring the behaviour matches the expected.
- Check grafana metrics at `localhost:3001`.
- Check that the RLN membership was registered in the block explorer `localhost:3000`.