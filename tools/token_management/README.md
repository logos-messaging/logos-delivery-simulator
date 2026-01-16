# token-management

Test utility for [TestStableToken](https://github.com/logos-messaging/logos-messaging-rlnv2-contract/blob/main/test/TestStableToken.sol) used in the Logos Messaging RLN v2 contract tests.

Given the token contract address and an Ethereum JSON-RPC endpoint, it allows minting and transferring TestStableToken tokens.
Given the contract address, it can also query allowances.

Details about the use of TestStableToken can be found in the [TST README](https://github.com/logos-messaging/logos-messaging-rlnv2-contract/blob/main/test/README.md)

## Configuration

Set the following environment variables (or use a `.env` file):

- `TOKEN_CONTRACT_ADDRESS`: The token contract proxy address
- `RLN_CONTRACT_ADDRESS`: The RLN contract proxy address
- `RLN_RELAY_ETH_CLIENT_ADDRESS`: The Ethereum JSON-RPC endpoint
- `ETH_FROM`: The default user account address
- `PRIVATE_KEY`: Private key for write operations (transfer, mint)

## Usage

The `interactions.py` script provides a CLI interface for all token operations.

### Read-Only Commands (no PRIVATE_KEY required)

Get total supply:
```bash
python3 tools/token_management/interactions.py total-supply
```

Get max supply:
```bash
python3 tools/token_management/interactions.py max-supply
```

Get contract owner:
```bash
python3 tools/token_management/interactions.py owner
```

Get implementation address:
```bash
python3 tools/token_management/interactions.py implementation
```

Get balance (defaults to USER_ACCOUNT_ADDRESS from env):
```bash
python3 tools/token_management/interactions.py balance
python3 tools/token_management/interactions.py balance 0xYourAddress
```

Get allowance (defaults to USER_ACCOUNT_ADDRESS and RLN_CONTRACT_PROXY_ADDRESS):
```bash
python3 tools/token_management/interactions.py allowance
python3 tools/token_management/interactions.py allowance 0xOwner 0xSpender
```

Check if address is a minter (defaults to USER_ACCOUNT_ADDRESS):
```bash
python3 tools/token_management/interactions.py is-minter
python3 tools/token_management/interactions.py is-minter 0xAddress
```

### Write Commands (PRIVATE_KEY required)

All write commands accept an optional `--private-key` flag to specify a custom private key. If not provided, the `PRIVATE_KEY` environment variable will be used.

Transfer tokens:
```bash
python3 tools/token_management/interactions.py transfer 0xRecipient 100.5
python3 tools/token_management/interactions.py transfer 0xRecipient 100.5 --private-key 0xYourPrivateKey
```

Mint tokens:
```bash
python3 tools/token_management/interactions.py mint 0xRecipient 1000
python3 tools/token_management/interactions.py mint 0xRecipient 1000 --private-key 0xYourPrivateKey
```

Approve spender to use tokens:
```bash
python3 tools/token_management/interactions.py approve 0xSpender 500
python3 tools/token_management/interactions.py approve 0xSpender 500 --private-key 0xYourPrivateKey
```

### Help

View all available commands:
```bash
python3 tools/token_management/interactions.py --help
```
