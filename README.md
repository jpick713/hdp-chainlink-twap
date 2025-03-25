# Setting Up and Running the Chainlink TWAP Validator

## Docker Setup Instructions

For environments where dependencies like OpenSSL 3.0 or GLIBC 2.34 aren't available, use Docker to create a compatible environment:

```bash
# Start from project root directory
cd structured-product/hdp-verify
docker run -it -v $(pwd):/project ubuntu:22.04
```

## Inside the Docker Container

Install required dependencies:

```bash
# Install basic tools
apt update
apt install -y curl git

# Install HDP CLI
curl -fsSL https://raw.githubusercontent.com/HerodotusDev/hdp-cairo/main/install-cli.sh | bash

# Install Scarb (Cairo package manager)
curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash

# Set up environment variables
export PATH=$PATH:/root/.local/bin
export HDP_DRY_RUN_PATH="/root/.local/share/hdp/dry_run_compiled.json"
export HDP_SOUND_RUN_PATH="/root/.local/share/hdp/sound_run_compiled.json"
```

## Building and Running

Navigate to the project directory and build:

```bash
cd /project/chainlink_twap_validator
scarb clean
scarb build
```

Execute HDP steps:

```bash
# 1. Run a dry run to simulate execution and identify needed proofs
hdp-cli dry-run -m target/dev/chainlink_twap_validator_module.compiled_contract_class.json --print_output --inputs input.json

# 2. Fetch required on-chain proofs
hdp-cli fetch-proofs

# 3. Run with verified on-chain data
hdp-cli sound-run -m target/dev/chainlink_twap_validator_module.contract_class.json --print_output
```

## Troubleshooting

- Ensure input.json is properly formatted and in the correct directory
- If seeing "missing field 'offset'" errors, confirm you're using the compiled contract class
- For RPC errors, verify your environment has the proper RPC endpoints configured

## Example input.json
[
    {
        "visibility": "public",
        "value": "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6" // Base asset oracle address (USDC/USD on mainnet)
    },
    {
        "visibility": "public",
        "value": "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c" // Quote asset oracle address (BTC/USD on mainnet)
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
    }
]

## To remove target directory with elevated permissions
sudo rm -rf /home/jpick713/structured-product/hdp-verify/chainlink_twap_validator/target


