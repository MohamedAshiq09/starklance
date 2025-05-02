#!/bin/bash

# Build the project
echo "Building the project..."
scarb build

# Get the Sierra class hash
CLASS_FILE="target/dev/freelance_marketplace_FreelanceMarketplace.sierra.json"
CASM_FILE="target/dev/freelance_marketplace_FreelanceMarketplace.casm.json"

# Check if Starkli is installed
if ! command -v starkli &> /dev/null; then
    echo "Starkli is not installed. Please install it first."
    exit 1
fi

# Set up environment variables (modify these to match your setup)
NETWORK="goerli-1"
ACCOUNT_FILE="$HOME/.starkli-wallets/account.json"
KEYSTORE_FILE="$HOME/.starkli-wallets/deployer_keystore.json"

# Prompt for contract parameters
read -p "Enter owner address: " OWNER_ADDRESS
read -p "Enter payment token address: " PAYMENT_TOKEN_ADDRESS
read -p "Enter platform fee in basis points (e.g., 250 for 2.5%): " PLATFORM_FEE_BPS
read -p "Enter platform wallet address: " PLATFORM_WALLET

# Declare the contract
echo "Declaring the contract..."
RESULT=$(starkli declare $CLASS_FILE \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --network $NETWORK \
  --compiler-version 2.5.3 \
  --watch)

# Extract class hash from the result
CLASS_HASH=$(echo $RESULT | grep -oP 'Class hash: \K[0-9a-f]+')
echo "Contract declared with class hash: $CLASS_HASH"

# Deploy the contract
echo "Deploying the contract..."
RESULT=$(starkli deploy $CLASS_HASH \
  $OWNER_ADDRESS $PAYMENT_TOKEN_ADDRESS $PLATFORM_FEE_BPS $PLATFORM_WALLET \
  --account $ACCOUNT_FILE \
  --keystore $KEYSTORE_FILE \
  --network $NETWORK \
  --watch)

# Extract contract address from the result
CONTRACT_ADDRESS=$(echo $RESULT | grep -oP 'Contract address: \K[0-9a-f]+')
echo "Contract deployed to address: $CONTRACT_ADDRESS"

# Save the contract address to a file
echo $CONTRACT_ADDRESS > .contract_address
echo "Contract address saved to .contract_address"