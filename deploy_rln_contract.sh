#!/bin/sh

set -e

# 1. Install foundry and pnpm
curl -L https://foundry.paradigm.xyz | bash
export PATH="$PATH:$HOME/.foundry/bin"
foundryup --install "${FOUNDRY_VERSION:-v1.7.1}"

echo "installing pnpm..."
npm install -g pnpm

# 2. Clone and build the repository
if [ ! -d "waku-rlnv2-contract" ]; then
    git clone https://github.com/waku-org/waku-rlnv2-contract.git
fi

if [ -z "$RLN_CONTRACT_REPO_COMMIT" ]; then
    echo "RLN_CONTRACT_REPO_COMMIT is not set"
    exit 1
fi

cd /waku-rlnv2-contract
git checkout $RLN_CONTRACT_REPO_COMMIT

# 3. Compile Contract Repo
echo "forge install..."
forge install

# Workaround: gitpkg.vercel.app returns HTTP 402, so fetch @zk-kit/imt.sol
# directly from GitHub at the same commit the URL pinned, and redirect
# package.json at the local copy via file: protocol before pnpm install.
ZK_KIT_COMMIT=0699fd1e5ad3683ae0090e0626f75d7834145500
echo "Fetching @zk-kit/imt.sol from GitHub at $ZK_KIT_COMMIT..."
rm -rf /tmp/zk-kit local-deps/imt.sol
git clone --quiet https://github.com/privacy-scaling-explorations/zk-kit.git /tmp/zk-kit
(cd /tmp/zk-kit && git checkout --quiet $ZK_KIT_COMMIT)
mkdir -p local-deps
cp -r /tmp/zk-kit/packages/imt.sol local-deps/imt.sol
sed -i 's|"@zk-kit/imt.sol": *"https://gitpkg.vercel.app/[^"]*"|"@zk-kit/imt.sol": "file:./local-deps/imt.sol"|' package.json
rm -f pnpm-lock.yaml

echo "pnpm install..."
pnpm install
echo "forge build..."
forge build

# 4. Export environment variables
export RCL_URL=$RCL_URL
export PRIVATE_KEY=$PRIVATE_KEY
export ETH_FROM=$ETH_FROM
# Dummy values
export API_KEY_ETHERSCAN=123
export API_KEY_CARDONA=123
export API_KEY_LINEASCAN=123

# Helper function to validate Ethereum addresses
validate_address() {
    local address="$1"
    local name="$2"
    
    if [ -z "$address" ]; then
        echo "Error: Failed to extract $name address"
        exit 1
    fi
    
    if ! echo "$address" | grep -qE "^0x[a-fA-F0-9]{40}$"; then
        echo "Error: Invalid $name address format: $address"
        exit 1
    fi
    
    echo "Successfully extracted $name address: $address"
}

# 5. Deploy the TestToken Proxy with the TestToken implementation contracts
printf "\nDeploying TestToken Proxy (ERC20 Token Contract)...\n"
DEPLOY_TST_PROXY_OUTPUT=$(ETH_FROM=$ETH_FROM forge script script/DeployTokenWithProxy.s.sol:DeployTokenWithProxy --broadcast -vv --rpc-url http://foundry:8545 --private-key $PRIVATE_KEY)
if [ $? -ne 0 ]; then
    echo "Error: TestToken Proxy deployment failed"
    echo "Forge output: $DEPLOY_TST_PROXY_OUTPUT"
    exit 1
fi

export PROXY_TOKEN_ADDRESS=$(echo "$DEPLOY_TST_PROXY_OUTPUT" | grep -o "0: address 0x[a-fA-F0-9]\{40\}" | head -n1 | cut -d' ' -f3)
validate_address "$PROXY_TOKEN_ADDRESS" "TestToken Proxy"
export TOKEN_ADDRESS=$PROXY_TOKEN_ADDRESS

printf "\nDeploying LinearPriceCalculator Contract...\n"
forge script script/Deploy.s.sol --broadcast -vv --rpc-url http://foundry:8545 --tc DeployPriceCalculator --private-key $PRIVATE_KEY
if [ $? -ne 0 ]; then
    echo "Error: LinearPriceCalculator deployment failed"
    exit 1
fi
echo "LinearPriceCalculator deployment completed successfully"

printf "\nDeploying RLN contract...\n"
forge script script/Deploy.s.sol --broadcast -vv --rpc-url http://foundry:8545 --tc DeployWakuRlnV2 --private-key $PRIVATE_KEY
if [ $? -ne 0 ]; then
    echo "Error: RLN contract deployment failed"
    exit 1
fi
echo "RLN contract deployment completed successfully"

printf "\nDeploying Proxy contract...\n"
DEPLOY_WAKURLN_PROXY_OUTPUT=$(ETH_FROM=$ETH_FROM forge script script/Deploy.s.sol --broadcast -vvv --rpc-url http://foundry:8545 --tc DeployProxy --private-key $PRIVATE_KEY)
if [ $? -ne 0 ]; then
    echo "Error: Proxy contract deployment failed"
    echo "Forge output: $DEPLOY_WAKURLN_PROXY_OUTPUT"
    exit 1
fi

export RLN_CONTRACT_ADDRESS=$(echo "$DEPLOY_WAKURLN_PROXY_OUTPUT" | grep -o "0: address 0x[a-fA-F0-9]\{40\}" | head -n1 | cut -d' ' -f3)
validate_address "$RLN_CONTRACT_ADDRESS" "RLN Proxy"

# 6. Contract deployment completed
printf "\nContract deployment completed successfully"
printf "\nTOKEN_ADDRESS: $TOKEN_ADDRESS"
printf "\nRLN_CONTRACT_ADDRESS: $RLN_CONTRACT_ADDRESS"
printf "\nEach account registering a membership needs to first mint the token and approve the contract to spend it on their behalf."