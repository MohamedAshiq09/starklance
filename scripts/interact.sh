#!/bin/bash

# Check if contract address exists
if [ ! -f .contract_address ]; then
    echo "Contract address not found. Please deploy the contract first."
    exit 1
fi

# Load contract address
CONTRACT_ADDRESS=$(cat .contract_address)

# Check if Starkli is installed
if ! command -v starkli &> /dev/null; then
    echo "Starkli is not installed. Please install it first."
    exit 1
fi

# Set up environment variables (modify these to match your setup)
NETWORK="goerli-1"
ACCOUNT_FILE="$HOME/.starkli-wallets/account.json"
KEYSTORE_FILE="$HOME/.starkli-wallets/deployer_keystore.json"

# Display menu
echo "Freelance Marketplace Contract Interaction"
echo "Contract address: $CONTRACT_ADDRESS"
echo ""
echo "Select an action:"
echo "1. Create a job"
echo "2. Apply for a job"
echo "3. Submit work"
echo "4. Approve work"
echo "5. Dispute a job"
echo "6. Get job details"
echo "7. Exit"

read -p "Enter your choice: " CHOICE

case $CHOICE in
    1) # Create a job
        read -p "Enter payment amount (in wei): " PAYMENT
        read -p "Enter deadline (unix timestamp): " DEADLINE
        read -p "Enter job description: " DESCRIPTION
        
        starkli invoke $CONTRACT_ADDRESS create_job $PAYMENT $DEADLINE $DESCRIPTION \
            --account $ACCOUNT_FILE \
            --keystore $KEYSTORE_FILE \
            --network $NETWORK \
            --watch
        ;;
        
    2) # Apply for a job
        read -p "Enter job ID: " JOB_ID
        
        starkli invoke $CONTRACT_ADDRESS apply_for_job $JOB_ID \
            --account $ACCOUNT_FILE \
            --keystore $KEYSTORE_FILE \
            --network $NETWORK \
            --watch
        ;;
        
    3) # Submit work
        read -p "Enter job ID: " JOB_ID
        
        starkli invoke $CONTRACT_ADDRESS submit_work $JOB_ID \
            --account $ACCOUNT_FILE \
            --keystore $KEYSTORE_FILE \
            --network $NETWORK \
            --watch
        ;;
        
    4) # Approve work
        read -p "Enter job ID: " JOB_ID
        
        starkli invoke $CONTRACT_ADDRESS approve_work $JOB_ID \
            --account $ACCOUNT_FILE \
            --keystore $KEYSTORE_FILE \
            --network $NETWORK \
            --watch
        ;;
        
    5) # Dispute a job
        read -p "Enter job ID: " JOB_ID
        read -p "Enter reason: " REASON
        
        starkli invoke $CONTRACT_ADDRESS dispute_job $JOB_ID $REASON \
            --account $ACCOUNT_FILE \
            --keystore $KEYSTORE_FILE \
            --network $NETWORK \
            --watch
        ;;
        
    6) # Get job details
        read -p "Enter job ID: " JOB_ID
        
        starkli call $CONTRACT_ADDRESS get_job $JOB_ID \
            --account $ACCOUNT_FILE \
            --network $NETWORK
        ;;
        
    7) # Exit
        echo "Exiting..."
        exit 0
        ;;
        
    *) # Invalid choice
        echo "Invalid choice. Exiting..."
        exit 1
        ;;
esac