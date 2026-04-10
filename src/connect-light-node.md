# Connect external light node

> **Protocol exercised:** Lightpush + RLN — a resource-restricted client publishes messages through a full [logos-delivery](https://github.com/logos-messaging/logos-delivery) node using the lightpush protocol, with RLN proofs fetched directly from the contract.

By using [go-waku-light](https://github.com/alrevuelta/go-waku-light), you can connect one or multiple light clients to the network. This utility can be configured to send messages at a given rate using a given peer as `light-push`. It will register an RLN membership at startup. Bear in mind that it should be configured with the same contract and `user-message-limit` as the rest of the network. You should modify the `lightpush-peer`.

Note that if you spin up multiple services like this using the same `priv-key` some of the transactions registering the RLN membership may fail due to the nonce being repeated. This can be fixed by using multiple keys or waiting for the registration to be completed before spinning up the next process.

- ⚠️ change `lightpush-peer` to the node you wish. Note that the multiaddress is logged by every peer at startup.

```jsx
docker run --network logos-delivery-simulator_simulation alrevuelta/go-waku-light:4fabb22 \
--eth-endpoint=http://foundry:8545 \
--contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
send-messages-loop \
--priv-key=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
--user-message-limit=1 \
--message="light client sending a rln message" \
--content-topic=/basic2/1/test/proto \
--pubsub-topic=/waku/2/rs/66/0 \
--cluster-id=66 \
--lightpush-peer=/ip4/10.2.0.16/tcp/60000/p2p/16Uiu2HAmAA99YfoLitSXgY1bHaqjaTKhyrU4M4y3D1rVj1bmcgL8 \
--message-every-secs=5 \
--epoch-size-secs=1
```

Note that in some examples, it could be interesting to run multiple instances, either in parallel or one after the other. For example if you set `amount-message-to-send=1` this will send just 1 message and exit. You can for example run this 100 times, where a fresh RLN membership will be created on every run, create a new peerId, send a message and exit.

```bash
for i in {1..5}; do
    docker run --rm --network logos-delivery-simulator_simulation alrevuelta/go-waku-light:4fabb22 \
    --eth-endpoint=http://foundry:8545 \
    --contract-address=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
    send-messages-loop \
    --priv-key=ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --user-message-limit=1 \
    --message="light client sending a rln message" \
    --content-topic=/basic2/1/test/proto \
    --pubsub-topic=/waku/2/rs/66/0 \
    --cluster-id=66 \
    --lightpush-peer=/ip4/10.2.0.16/tcp/60000/p2p/16Uiu2HAm6a4kUT7YutsbwgQcmWw5VLzN3zj1StwiBVf2LUH9kb4A \
    --message-every-secs=5 \
    --epoch-size-secs=1 \
    --amount-message-to-send=1
    
    if [ $? -ne 0 ]; then
        echo "Command failed at iteration $i"
        break
    fi
done
```

🎯**Goals**:

- Tests lightpush end to end, where proofs are fetched directly from the contract

👀**Observability**:

- Check the logs of the node you provided as `lightpush-peer`.
- Check grafana metrics at `localhost:3001`.
- Check that the RLN membership was registered in the block explorer `localhost:3000`.