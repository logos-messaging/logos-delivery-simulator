#!/bin/sh

ANVIL_CONFIG_PATH=${ANVIL_CONFIG_PATH:-/shared/anvil-config.txt}

# Check Linux Distro Version - it can differ depending on the nwaku image used
OS=$(cat /etc/os-release)
if echo $OS | grep -q "Debian"; then
    echo "The operating system is Debian."
    apt update
    apt install -y dnsutils
    apt install -y jq
elif echo $OS | grep -q "Alpine"; then
    echo "The operating system is Alpine."
    apk add bind-tools
    apk add jq
fi

if test -f .env; then
  echo "Using .env file"  
  . $(pwd)/.env
fi

IP=$(ip a | grep "inet " | grep -Fv 127.0.0.1 | sed 's/.*inet \([^/]*\).*/\1/')

# Function to extract IP address from URL, resolve the IP and replace it in the original URL
get_ip_address_and_replace() {
    local url=$1
    local domain_name=$(echo $RPC_URL | awk -F[/:] '{print $4}')
    local ip_address=$(dig +short $domain_name)
    valid_rpc_url="$(echo "$url" | sed "s/$domain_name/$ip_address/g")"
    echo $valid_rpc_url
}

# the format of the RPC URL is checked in the generateRlnKeystore command and hostnames are not valid
pattern="^(https?):\/\/((localhost)|([\w_-]+(?:(?:\.[\w_-]+)+)))(:[0-9]{1,5})?([\w.,@?^=%&:\/~+#-]*[\w@?^=%&\/~+#-])*"
# Perform regex matching
if echo "$RPC_URL" | grep -q "$pattern"; then
    echo "RPC URL is valid"
else
    echo "RPC URL is invalid: $RPC_URL. Attempting to resolve hostname."
    resolved_rpc_url="$(get_ip_address_and_replace $RPC_URL)"
    if [ -z "$resolved_rpc_url" ]; then
        echo -e "Failed to retrieve IP address for $RPC_URL\n"
    else
        echo -e "Resolved RPC URL for $RPC_URL: $resolved_rpc_url"
        RPC_URL="$resolved_rpc_url"
    fi
fi

#Function to get the index of the container and use it to retrieve a private key to be used to generate the keystore, allowing for either dash or underscore container name format (for docker-compose backward compatibility)
get_private_key(){

  # Read the JSON file
  json_content=$(cat "$ANVIL_CONFIG_PATH")

  # Check if json_content has a value
  if [ -z "$json_content" ]; then
    echo "Error: Failed to read the JSON file or the file is empty." >&2
    return 1
  fi

  # Extract private_keys json array using jq
  private_keys=$(echo "$json_content" | jq -r '.private_keys[]')

  CNTR=`dig -x $IP +short | cut -d'.' -f1`
  INDEX=`echo $CNTR | sed 's/.*[-_]\([0-9]*\)/\1/'`

  if [ $? -ne 0 ] || [ -z "$INDEX" ]; then
    echo "Error: Failed to determine the replica index from IP." >&2
    return 1
  fi


  # iterate through list of private keys and get the one corresponding to the container index
  # we need to iterate because array objects cannot be used in /bin/ash (Alpine) and a separate script would need to be called to use bash
  current_index=1
  for key in $private_keys
  do
    if [ $current_index -eq $INDEX ]; then
      pk=$key
      echo $key
      break
    fi
    current_index=$((current_index+1))
  done

  if [ -z "$pk" ]; then
    echo "Error: Failed to get private key for the container with index=$INDEX." >&2
    return 1
  fi
}

if test -f .$RLN_CREDENTIAL_PATH; then
  echo "$RLN_CREDENTIAL_PATH already exists. Use it instead of creating a new one."
else
  private_key="$(get_private_key)"
  echo "Private key: $private_key"

  echo "Generating RLN keystore"
  /usr/bin/wakunode generateRlnKeystore \
    --rln-relay-eth-client-address="$RPC_URL" \
    --rln-relay-eth-private-key=$private_key  \
    --rln-relay-eth-contract-address=$RLN_CONTRACT_ADDRESS \
    --rln-relay-cred-path=$RLN_CREDENTIAL_PATH \
    --rln-relay-cred-password=$RLN_CREDENTIAL_PASSWORD \
    --rln-relay-user-message-limit=$RLN_RELAY_MSG_LIMIT \
    --rln-relay-epoch-sec=$RLN_RELAY_EPOCH_SEC \
    --log-level=DEBUG \
    --execute
fi

echo "I am a nwaku node"

RETRIES=${RETRIES:=10}

while [ -z "${BOOTSTRAP_ENR}" ] && [ ${RETRIES} -ge 0 ]; do
  BOOTSTRAP_ENR=$(wget -qO- http://bootstrap:8645/debug/v1/info --header='Content-Type:application/json' 2> /dev/null | sed 's/.*"enrUri":"\([^"]*\)".*/\1/');
  echo "Bootstrap node not ready, retrying (retries left: ${RETRIES})"
  sleep 1
  RETRIES=$(( $RETRIES - 1 ))
done

if [ -z "${BOOTSTRAP_ENR}" ]; then
   echo "Could not get BOOTSTRAP_ENR and none provided. Failing"
   exit 1
fi

echo "Using bootstrap node: ${BOOTSTRAP_ENR}"
QUIC_ARGS=""
[ "${QUIC_SUPPORT:-true}" = "true" ] && QUIC_ARGS="--quic-support=true"
exec /usr/bin/wakunode\
      --relay=true\
      --lightpush=true\
      --max-connections=250\
      --rest=true\
      --rest-address=0.0.0.0\
      --rest-port=8645\
      --rln-relay=true\
      --rln-relay-dynamic=true\
      --rln-relay-eth-client-address="$RPC_URL"\
      --rln-relay-eth-contract-address=$RLN_CONTRACT_ADDRESS\
      --rln-relay-cred-path=$RLN_CREDENTIAL_PATH\
      --rln-relay-cred-password=$RLN_CREDENTIAL_PASSWORD\
      --rln-relay-epoch-sec=$RLN_RELAY_EPOCH_SEC\
      --rln-relay-user-message-limit=$RLN_RELAY_MSG_LIMIT\
      --rln-relay-chain-id=1234\
      --discv5-discovery=true\
      --discv5-enr-auto-update=True\
      --log-level=DEBUG\
      --metrics-server=True\
      --metrics-server-address=0.0.0.0\
      --discv5-bootstrap-node=${BOOTSTRAP_ENR}\
      --nat=extip:${IP}\
      --shard=0\
      --cluster-id=66 $QUIC_ARGS
