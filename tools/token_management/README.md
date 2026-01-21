# token-management

CLI utility for interacting with the [TestStableToken](https://github.com/logos-messaging/logos-messaging-rlnv2-contract/blob/main/test/TestStableToken.sol) ERC-20 used by the Logos Messaging RLN v2 contract tests.

Point it at a deployed token contract (proxy) and an Ethereum JSON-RPC endpoint to:
- Read token state (e.g. balance, allowance, total/max supply, owner, proxy implementation).
- Perform write operations like mint/transfer/approve and minter/ownership management (requires `PRIVATE_KEY`).

For the semantics and intended use of `TestStableToken` itself, see the [TST README](https://github.com/logos-messaging/logos-messaging-rlnv2-contract/blob/main/test/README.md).

## Configuration

Set the following environment variables (or use a `.env` file):

- `TOKEN_CONTRACT_ADDRESS`: The token contract proxy address
- `RLN_CONTRACT_ADDRESS`: The RLN contract proxy address
- `RLN_RELAY_ETH_CLIENT_ADDRESS`: The Ethereum JSON-RPC endpoint
- `ETH_FROM`: The default user account address of the deployer/owner of the TestStableToken contract
- `PRIVATE_KEY`: Private key for the ETH_FROM account, it will lbe used for write operations (transfer, mint)

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

Get token contract owner:
```bash
python3 tools/token_management/interactions.py owner
```

Get token implementation address:
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

Transfer contract ownership:
```bash
python3 tools/token_management/interactions.py transfer-ownership 0xNewOwner
python3 tools/token_management/interactions.py transfer-ownership 0xNewOwner --private-key 0xYourPrivateKey
```

Add minter role to an account:
```bash
python3 tools/token_management/interactions.py add-minter 0xAccount
python3 tools/token_management/interactions.py add-minter 0xAccount --private-key 0xYourPrivateKey
```

Remove minter role from an account:
```bash
python3 tools/token_management/interactions.py remove-minter 0xAccount
python3 tools/token_management/interactions.py remove-minter 0xAccount --private-key 0xYourPrivateKey
```

### Help

View all available commands:
```bash
python3 tools/token_management/interactions.py --help
```
