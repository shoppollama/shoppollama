#!/bin/bash

# Deploy fix for infinite thinking state
# This script updates the deployed application with timeout fixes

echo "Deploying fix for AI thinking state..."

# Connect to EC2 and navigate to app directory
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 << 'EOF'
cd /home/ec2-user/shoppollama

# Pull latest changes
git pull origin main

# Build and restart the application
mix deps.get --only prod
MIX_ENV=prod mix compile
cd assets
npm ci
npm run deploy
cd ..
sudo systemctl restart shoppollama

echo "Deployment complete!"
EOF

echo "Fix deployed successfully!"
