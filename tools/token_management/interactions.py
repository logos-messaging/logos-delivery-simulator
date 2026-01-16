import os
from web3 import Web3
from dotenv import load_dotenv

# Load environment variables from .env if present
load_dotenv()

TOKEN_CONTRACT_PROXY_ADDRESS = os.getenv("TOKEN_CONTRACT_ADDRESS", "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512")
TOKEN_CONTRACT_OWNER_ADDRESS = os.getenv("ETH_FROM", "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266")  # Replace with actual owner address
RLN_CONTRACT_PROXY_ADDRESS = os.getenv("RLN_CONTRACT_ADDRESS", "0x0165878A594ca255338adfa4d48449f69242Eb8F")  # Replace with actual RLN contract address
RPC_URL = os.getenv("RLN_RELAY_ETH_CLIENT_ADDRESS", "http://foundry:8545") #Replace 'foundry' with the containers actual IP or replace entirely with your own RPC URL
USER_ACCOUNT_ADDRESS = os.getenv("ETH_FROM", "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266")  # Replace with actual user address
CONTRACT_OWNER_PRIVATE_KEY = os.getenv("PRIVATE_KEY", "PK")  # Replace 'PK' with your private key or set in .env


# Standard ERC20 ABI (truncated to main functions)
ERC20_ABI = [
    {"constant":True,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"},
    {"constant":True,"inputs":[{"name":"_owner","type":"address"}, {"name":"_spender", "type":"address"}],"name":"allowance","outputs":[{"name":"allowance","type":"uint256"}],"type":"function"},
    {"constant":False,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"success","type":"bool"}],"type":"function"},
    {"constant":False,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"type":"function"},
    {"constant":False,"inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"name":"mint","outputs":[],"type":"function"},
    {"constant":True,"inputs":[{"name":"account","type":"address"}],"name":"isMinter","outputs":[{"name":"","type":"bool"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"maxSupply","outputs":[{"name":"","type":"uint256"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"owner","outputs":[{"name":"","type":"address"}],"type":"function"},
    {"constant":True,"inputs":[],"name":"implementation","outputs":[{"name":"","type":"address"}],"type":"function"}
]

w3 = Web3(Web3.HTTPProvider(RPC_URL))
contract = w3.eth.contract(address=Web3.to_checksum_address(TOKEN_CONTRACT_PROXY_ADDRESS), abi=ERC20_ABI)



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

def get_total_supply():
    return contract.functions.totalSupply().call()

def get_max_supply():
    return contract.functions.maxSupply().call()

def get_owner():
    return contract.functions.owner().call()

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
