# Connect external store node

> **Protocol exercised:** Store — a [logos-delivery](https://github.com/logos-messaging/logos-delivery) node with persistent storage joins the network, archives messages it sees on the relay, and serves historical queries via the store protocol.

One or more external store nodes can be connected to the logos-delivery-simulator network by using configuration similar to that shown below. The store node(s) can use the DB as backend from an existing staging or production system DB or a custom one. When connecting to any DB ensure that the `store-message-retention-policy` matches that of the system.
The staticnode that the store node connects to can be any existing node in the logos-delivery-simulator network, alternatively use the discv5 configuration.

```bash
 --discv5-discovery=true \
 --discv5-enr-auto-update=True \
 --discv5-bootstrap-node=BOOTSTRAP_ENR\
```

The store node can be queried via the [waku rest API]( https://waku-org.github.io/waku-rest-api/#get-/store/v3/messages).
An easy way to find a message hash to query is by checking the store node logs for the `message archived` message:

```bash
docker logs nwaku_storenode_1 | grep -i "message archived"
```
The store node will need to have log-level set to DEBUG for this logging to be available.

The [message-finder](https://github.com/waku-org/message-finder) tool could also be useful for store node testing.


```bash
docker run -it --network logos-delivery-simulator_simulation --name nwaku_storenode_1 -d harbor.status.im/wakuorg/nwaku:latest \
    --relay=true\
    --rest=true\
    --rest-address=0.0.0.0\
    --rest-port=8645\
    --log-level=DEBUG\
    --pubsub-topic=/waku/2/rs/66/0\
    --cluster-id=66\
    --metrics-server=true\
    --discv5-discovery=true\
    --discv5-enr-auto-update=true\
    --store=true\
    --store-message-db-url=<e.g. postgres://pguser:pgpasswrd@127.0.0.1:5432/postgres>\
    --store-message-retention-policy=size:120GB\
    --staticnode=/ip4/0.0.0.0/tcp/60000/p2p/16Uiu2HAmC8Fe4Egsq6AKubmBPr52TQmwc26yoCkszwo6dfQncZ4m\
    --nodekey=5978783f8b1a16795032371fff7a526af352d9dca38179af7d71c0122942fa20

```



🎯**Goals**:

- Connect a store node(s) to the network for ad hoc store protocol testing.
- Verify that store queries get the expected results.

👀**Observability**:

- Check the logs of the newly connected store node, ensuring the behaviour matches the expected.