# Inject traffic

> **Protocol exercised:** Relay (gossipsub) — messages are published via the REST API and propagated to every node through the relay protocol from [logos-delivery](https://github.com/logos-messaging/logos-delivery). The REST API itself is documented at [waku-org.github.io/waku-rest-api](https://waku-org.github.io/waku-rest-api/).

In order to inject traffic into the network, we can use the REST API of each `logos-delivery` node. We have a simple dockerized script in [rest-traffic](https://github.com/alrevuelta/rest-traffic), that can perform this task. In the following command we run a docker container connected to the logos-delivery-simulator network. This script will inject a message every `delay-seconds` with a size of `msg-size-kbytes` into a given `pubsub-topic`. Note that in `multiple-nodes` you can configure the nodes that will publish messages, where `[1..5]` will publish to nodes 1, 2, 3, 4, 5. You can publish to a single node (e.g. node 1) by using `[1..1]`.

```jsx
docker run -it --network logos-delivery-simulator_simulation alrevuelta/rest-traffic:d936446 \
--delay-seconds=10 \
--msg-size-kbytes=5 \
--pubsub-topic=/waku/2/rs/66/0 \
--multiple-nodes="http://logos-delivery-simulator_nwaku_[1..5]:8645"
```

Note that the REST API doesn’t allow to publish messages exceeding the rate limit, so this tool can’t be used to test beyond the rate limits.

🎯**Goals**:

- Test message publishing via the REST API and that they are valid across the network.
- Test the network under different message load: rates and sizes.

👀**Observability**:

- Check the logs of each `nwaku` node, verifying the messages are correctly received via the API and forwarded to other nodes.
- Check grafana dashboard `localhost:3001` ”RLN Valid Messages Total” increases as expected.
