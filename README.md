# Setting Up and Running the Chainlink TWAP Validator

## Docker Setup Instructions

For environments where dependencies like OpenSSL 3.0 or GLIBC 2.34 aren't available, use Docker to create a compatible environment:

```bash
# Start from project root directory
cd structured-product/hdp-verify
docker run --rm -it -v $(pwd):/local ubuntu:22.04
```

## Inside the Docker Container - Building from Source

Install all required dependencies:

```bash
# Update and install system dependencies
apt update
apt install -y curl git build-essential libgmp3-dev pkg-config libssl-dev python3 python3-pip

# Install Python 3.9 (required by HDP)
apt install -y software-properties-common
add-apt-repository -y ppa:deadsnakes/ppa
apt update
apt install -y python3.9 python3.9-dev python3.9-venv

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Install Cairo 0 compiler (needed for HDP build)
pip3 install cairo-lang==0.11.0
export PATH=$PATH:$HOME/.local/bin

# Install Scarb (Cairo package manager)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash
export PATH=$PATH:$HOME/.local/bin

# Clone HDP repository with submodules
git clone --recurse-submodules https://github.com/HerodotusDev/hdp-cairo.git
cd hdp-cairo

# Build HDP
make
cargo build
```

## Set up environment variables

```bash
# Set paths for your project and HDP
export RPC_URL_ETHEREUM="your_ethereum_rpc_url"
export RPC_URL_HERODOTUS_INDEXER=https://staging.rs-indexer.api.herodotus.cloud/
export RPC_URL_STARKNET="your_starknet_rpc_url"
export HDP_CLI_PATH=$(pwd)/target/debug/hdp-cli
```

## Building and Running Your Contract

First, build your Cairo contract:

```bash
cd /local/chainlink_twap_validator
scarb clean
scarb build
```

Execute HDP steps using the built-from-source CLI:

```bash
# 1. Run a dry run to simulate execution and identify needed proofs
$HDP_CLI_PATH dry-run -m target/dev/chainlink_twap_validator_module.compiled_contract_class.json --print_output --inputs input-mainnet.json

# 2. Fetch required on-chain proofs
$HDP_CLI_PATH fetch-proofs

# 3. Run with verified on-chain data
$HDP_CLI_PATH sound-run -m target/dev/chainlink_twap_validator_module.contract_class.json --print_output
```

## Common Issues and Troubleshooting

- **Missing libraries**: If encountering `libssl.so.3` or GLIBC errors, use Docker as shown above
- **Cairo compile not found**: Ensure cairo-compile is in your PATH (should be in ~/.local/bin)
- **Python version issues**: HDP requires Python 3.9; verify with `python3.9 --version`
- **Storage errors**: Ensure you're using correct oracle addresses and block numbers
- **Contract format errors**: Make sure you're using the correct filename output by scarb build

## Example input.json
```json
[
   {
        "visibility": "public",
        "value": "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c" // Base asset oracle address (BTC/USD on mainnet)
    },   
   {
        "visibility": "public",
        "value": "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6" // Quote asset oracle address (USDC/USD on mainnet)
    },
    {
        "visibility": "public",
        "value": "0xF50C00" // Start block number (example block)
    },
    {
        "visibility": "public",
        "value": "0x5F5E100" // Barrier price (100000000 = 100.0 with 6 decimals)
    },
    {
        "visibility": "public",
        "value": "0x0" // Option type (0 = Put, 1 = Call)
    },
    {
        "visibility": "public",
        "value": "0x6" // Quote asset decimals
    },
]
```

## Code Debugging Tips

- When debugging roundID issues, remember to mask the value after shifting:
  ```rust
  // Apply bit shift of 4 bytes (32 bits) to the retrieved storage value
  let shifted_value = raw_storage_value / 0x100000000;  // Right shift by 32 bits
  let masked_value = shifted_value & 0xFFFFFFFF;  // Get only lowest 32 bits
  ```

- Add print statements to debug values:
  ```rust
  println!("Debug - value: {}", value);
  ```

- Check your sample count logic if getting assertion errors

## Cleaning Up

To remove target directory with elevated permissions:
```bash
sudo rm -rf /home/jpick713/structured-product/hdp-verify/chainlink_twap_validator/target
```