# Connect external full node


If you want to connect a node with some custom configuration to the existing Logos delivery network. Perhaps a different image or some other configuration, you can do it as follows. Bear in mind that if this node has other configuration (eg `rln-relay-epoch-sec` or `rln-relay-user-message-limit`) then it won’t behave properly.

- ⚠️set your own `staticnode`

```bash
docker run -it --network logos-delivery-simulator_simulation quay.io/wakuorg/nwaku-pr:2759-rln-v2 \
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
      --cluster-id=66
```

You can for example try to connect a node running in a different `cluster-id` or other weird scenarios.

You can also try to connect multiple nodes with a loop. Note the `&`. Remember to kill the new nodes once you are done.

```bash
for i in {1..5}; do
    docker run -it --network logos-delivery-simulator_simulation quay.io/wakuorg/nwaku-pr:2759-rln-v2 \
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
      --cluster-id=66 &
done
```

🎯**Goals**:

- Connect a different node(s) to the network for some ad hoc test.
- See how the network reacts to a node with different configuration.

👀**Observability**:

- Check the new node logs, ensuring the behaviour matches the expected.