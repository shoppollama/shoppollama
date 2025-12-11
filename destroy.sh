#!/bin/bash

# Destroy script for Shoppollama AWS infrastructure

set -e

echo "💥 Destroying Shoppollama AWS infrastructure..."

# Select stack (default to dev)
STACK=${1:-dev}
echo "🔧 Using stack: $STACK"

# Select stack
if ! pulumi stack select $STACK 2>/dev/null; then
    echo "❌ Stack $STACK does not exist."
    exit 1
fi

# Preview destruction
echo "👀 Previewing destruction..."
pulumi destroy --stack $STACK

# Ask for confirmation
echo ""
read -p "💥 Are you sure you want to destroy all resources? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Destroy
    echo "💥 Destroying..."
    pulumi destroy --stack $STACK --yes
    
    echo "✅ All resources destroyed successfully!"
else
    echo "❌ Destruction cancelled."
    exit 1
fi
