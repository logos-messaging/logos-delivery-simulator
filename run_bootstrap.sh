#!/bin/sh

IP=$(ip a | grep "inet " | grep -Fv 127.0.0.1 | sed 's/.*inet \([^/]*\).*/\1/')

echo "I am a bootstrap node"

# logos-delivery >= v0.39 ships logosdeliverynode; older images only have wakunode.
NODE_BIN=$(command -v logosdeliverynode || echo /usr/bin/wakunode)

exec $NODE_BIN\
      --relay=false\
      --rest=true\
      --rest-admin=true\
      --rest-address=0.0.0.0\
      --max-connections=300\
      --discv5-discovery=true\
      --discv5-enr-auto-update=True\
      --log-level=DEBUG\
      --metrics-server=True\
      --metrics-server-address=0.0.0.0\
      --nodekey=30348dd51465150e04a5d9d932c72864c8967f806cce60b5d26afeca1e77eb68\
      --nat=extip:${IP}\
      --cluster-id=66