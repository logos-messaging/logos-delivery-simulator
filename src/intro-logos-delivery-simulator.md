# Introduction to Logos Delivery Simulator

The [logos-delivery-simulator](https://github.com/logos-messaging/logos-delivery-simulator) tool allows simulating a Logos delivery network built on a set of interconnected [nwaku](https://github.com/waku-org/nwaku) nodes with the following features:

- Configurable amount of nodes. Limits depend on the machine and are upper bounded at around 200.
- Runs in a single machine, using `docker compose` to orchestrate the containers.
- It uses discv5 for peer discovery, using a common bootstrap node.
- It runs a custom ad hoc network, isolated from any existing public networks.
- It uses a freshly deployed private blockchain, with full control over it and minimum state to track.
- It deploys an RLN contract in the said private blockchain and configures it to be used by all nodes.
- It registers an RLN membership for each node in the network, configuring it to publish valid messages.
- It exposes each node’s API, so that it can be used to inject traffic into the network.
- Simple to run. Everything is automated. Requires two commands to run.

The main goals of `logos-delivery-simulator` include but are not limited to:
* Test new features in an end to end setup with multiple nodes.
* Use as a long-lived running network on the latest master, to anticipate breaking changes.
* Explore the delivery layer's limits under different loads and configurations.
* Offer a tool to debug problems in a controlled and easy to replicate environment.
