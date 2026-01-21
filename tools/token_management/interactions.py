import os
import json
from pathlib import Path
from web3 import Web3
from dotenv import load_dotenv

# Load environment variables from .env if present
load_dotenv()

TOKEN_CONTRACT_PROXY_ADDRESS = "0xd28d1a688b1cBf5126fB8B034d0150C81ec0024c"
RLN_CONTRACT_PROXY_ADDRESS = "0xB9cd878C90E49F797B4431fBF4fb333108CB90e6"
RPC_URL = "https://linea-sepolia.infura.io/v3/<YOUR_INFURA_PROJECT_ID>"  # Replace with your Infura project ID or load from env
USER_ACCOUNT_ADDRESS = "0xYourUserAccountAddressHere"  # Replace with user account address or load from env
CONTRACT_OWNER_PRIVATE_KEY = "PK" # Replace with actual private key or load from env

# Load the Token Stable Token Contract ABI
# TODO load the ABI from contract build artifacts
ABI_PATH = Path(__file__).with_name("token_abi.json")
TOKEN_ABI = json.loads(ABI_PATH.read_text(encoding="utf-8"))

w3 = Web3(Web3.HTTPProvider(RPC_URL))
contract = w3.eth.contract(address=Web3.to_checksum_address(TOKEN_CONTRACT_PROXY_ADDRESS), abi=TOKEN_ABI)


# Contract interaction helpers.
# For usage/examples and descriptions, see the argparse CLI section under the
# "main guard" at the bottom of this file: `if __name__ == "__main__":`.

def get_balance(address):
    balance = contract.functions.balanceOf(Web3.to_checksum_address(address)).call()
    decimals = contract.functions.decimals().call()
    return balance / (10 ** decimals)

def get_allowance(owner, spender):
    allowance = contract.functions.allowance(Web3.to_checksum_address(owner), Web3.to_checksum_address(spender)).call()
    decimals = contract.functions.decimals().call()
    return allowance / (10 ** decimals)

def transfer(to_address, amount, private_key=None):
    decimals = contract.functions.decimals().call()
    tx = contract.functions.transfer(Web3.to_checksum_address(to_address), int(amount * (10 ** decimals)))
    return send_tx(tx, private_key)

def mint(to_address, amount, private_key=None):
    decimals = contract.functions.decimals().call()
    tx = contract.functions.mint(Web3.to_checksum_address(to_address), int(amount * (10 ** decimals)))
    return send_tx(tx, private_key)

def approve(spender_address, amount, private_key=None):
    decimals = contract.functions.decimals().call()
    tx = contract.functions.approve(Web3.to_checksum_address(spender_address), int(amount * (10 ** decimals)))
    return send_tx(tx, private_key)

def is_minter(address):
    return contract.functions.isMinter(Web3.to_checksum_address(address)).call()

def add_minter(account_address, private_key=None):
    tx = contract.functions.addMinter(Web3.to_checksum_address(account_address))
    return send_tx(tx, private_key)

def remove_minter(account_address, private_key=None):
    tx = contract.functions.removeMinter(Web3.to_checksum_address(account_address))
    return send_tx(tx, private_key)

def get_total_supply():
    return contract.functions.totalSupply().call()

def get_max_supply():
    return contract.functions.maxSupply().call()

def get_owner():
    return contract.functions.owner().call()

def transfer_ownership(new_owner_address, private_key=None):
    tx = contract.functions.transferOwnership(Web3.to_checksum_address(new_owner_address))
    return send_tx(tx, private_key)

# Read: get implementation contract address (proxy, EIP-1967)
def get_implementation():
    # EIP-1967 implementation slot
    slot = int('0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC', 16)
    raw = w3.eth.get_storage_at(Web3.to_checksum_address(TOKEN_CONTRACT_PROXY_ADDRESS), slot)
    # The address is stored right-aligned in 32 bytes
    if len(raw) == 32:
        return raw[-20:].hex()
    return None

# Helper: send transaction
def send_tx(tx_func, private_key=None):
    if private_key is None:
        private_key = os.getenv("PRIVATE_KEY", "")
    if not private_key or private_key == "PK":
        raise ValueError("A valid PRIVATE_KEY is required for write operations. Provide it via parameter or environment variable.")
    acct = w3.eth.account.from_key(private_key)
    tx = tx_func.build_transaction({
        'from': acct.address,
        'nonce': w3.eth.get_transaction_count(acct.address),
        'gas': 200000,
        'gasPrice': w3.eth.gas_price
    })
    signed = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    print(f"Sent tx: {tx_hash.hex()}")
    return tx_hash

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Token Management CLI')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Read-only commands
    subparsers.add_parser('total-supply', help='Get total token supply')
    subparsers.add_parser('max-supply', help='Get max token supply')
    subparsers.add_parser('owner', help='Get contract owner')
    subparsers.add_parser('implementation', help='Get implementation contract address')

    balance_parser = subparsers.add_parser('balance', help='Get token balance')
    balance_parser.add_argument('address', nargs='?', default=USER_ACCOUNT_ADDRESS, help='Address to check (default: USER_ACCOUNT_ADDRESS from env)')

    allowance_parser = subparsers.add_parser('allowance', help='Get token allowance')
    allowance_parser.add_argument('owner', nargs='?', default=USER_ACCOUNT_ADDRESS, help='Owner address (default: USER_ACCOUNT_ADDRESS from env)')
    allowance_parser.add_argument('spender', nargs='?', default=RLN_CONTRACT_PROXY_ADDRESS, help='Spender address (default: RLN_CONTRACT_PROXY_ADDRESS from env)')

    minter_parser = subparsers.add_parser('is-minter', help='Check if address is a minter')
    minter_parser.add_argument('address', nargs='?', default=USER_ACCOUNT_ADDRESS, help='Address to check (default: USER_ACCOUNT_ADDRESS from env)')

    # Write commands
    transfer_parser = subparsers.add_parser('transfer', help='Transfer tokens (requires PRIVATE_KEY)')
    transfer_parser.add_argument('to', help='Recipient address')
    transfer_parser.add_argument('amount', type=float, help='Amount to transfer')
    transfer_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    mint_parser = subparsers.add_parser('mint', help='Mint tokens (requires PRIVATE_KEY)')
    mint_parser.add_argument('to', help='Recipient address')
    mint_parser.add_argument('amount', type=float, help='Amount to mint')
    mint_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    approve_parser = subparsers.add_parser('approve', help='Approve spender to use tokens (requires PRIVATE_KEY)')
    approve_parser.add_argument('spender', help='Spender address')
    approve_parser.add_argument('amount', type=float, help='Amount to approve')
    approve_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    transfer_ownership_parser = subparsers.add_parser('transfer-ownership', help='Transfer contract ownership (requires PRIVATE_KEY)')
    transfer_ownership_parser.add_argument('new_owner', help='New owner address')
    transfer_ownership_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    add_minter_parser = subparsers.add_parser('add-minter', help='Add minter role to account (requires PRIVATE_KEY)')
    add_minter_parser.add_argument('account', help='Account address to grant minter role to')
    add_minter_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    remove_minter_parser = subparsers.add_parser('remove-minter', help='Remove minter role from account (requires PRIVATE_KEY)')
    remove_minter_parser.add_argument('account', help='Account address to remove minter role from')
    remove_minter_parser.add_argument('--private-key', help='Private key (default: PRIVATE_KEY from env)')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
    elif args.command == 'total-supply':
        decimals = contract.functions.decimals().call()
        supply = get_total_supply()
        print(f"Total Supply: {supply / (10 ** decimals)}")
    elif args.command == 'max-supply':
        decimals = contract.functions.decimals().call()
        supply = get_max_supply()
        print(f"Max Supply: {supply / (10 ** decimals)}")
    elif args.command == 'owner':
        print(f"Owner: {get_owner()}")
    elif args.command == 'implementation':
        impl = get_implementation()
        print(f"Implementation: 0x{impl}" if impl else "Implementation: Not found")
    elif args.command == 'balance':
        balance = get_balance(args.address)
        print(f"Balance of {args.address}: {balance}")
    elif args.command == 'allowance':
        allowance = get_allowance(args.owner, args.spender)
        print(f"Allowance: {allowance}")
    elif args.command == 'is-minter':
        result = is_minter(args.address)
        print(f"{args.address} is minter: {result}")
    elif args.command == 'transfer':
        tx_hash = transfer(args.to, args.amount, getattr(args, 'private_key', None))
        print(f"Transfer complete: {tx_hash.hex()}")
    elif args.command == 'mint':
        tx_hash = mint(args.to, args.amount, getattr(args, 'private_key', None))
        print(f"Mint complete: {tx_hash.hex()}")
    elif args.command == 'approve':
        tx_hash = approve(args.spender, args.amount, getattr(args, 'private_key', None))
        print(f"Approve complete: {tx_hash.hex()}")
    elif args.command == 'transfer-ownership':
        tx_hash = transfer_ownership(args.new_owner, getattr(args, 'private_key', None))
        print(f"Transfer ownership complete: {tx_hash.hex()}")
    elif args.command == 'add-minter':
        tx_hash = add_minter(args.account, getattr(args, 'private_key', None))
        print(f"Add minter complete: {tx_hash.hex()}")
    elif args.command == 'remove-minter':
        tx_hash = remove_minter(args.account, getattr(args, 'private_key', None))
        print(f"Remove minter complete: {tx_hash.hex()}")
