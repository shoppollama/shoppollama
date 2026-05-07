#!/bin/bash

# Configuration for redeployment with proper database initialization
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="t4g-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-t4g-large-fixed"
KEY_NAME="shoppollama-key"
PUBLIC_IP="3.239.18.130"  # Using the existing instance IP

echo "🚀 Redeploying with proper database initialization..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Connect to existing instance and update deployment
echo "🔧 Updating deployment on existing instance..."

ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP << 'EOF'
cd /var/www/shoppollama

# Stop existing containers
sudo /usr/local/bin/docker-compose down

# Create new docker-compose.yml with proper initialization
sudo tee docker-compose.yml > /dev/null << 'DOCKEREOF'
version: "3.8"
services:
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    restart: unless-stopped
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0

  shoppollama:
    image: __ECR_IMAGE_URI__
    ports:
      - "4000:4000"
    restart: unless-stopped
    environment:
      - PORT=4000
      - MIX_ENV=prod
      - DATABASE_PATH=/app/data/shoppollama.db
      - SECRET_KEY_BASE=$(openssl rand -base64 64)
      - OLLAMA_BASE_URL=http://ollama:11434
      - PHX_SERVER=true
      - POOL_SIZE=10
    volumes:
      - ./data:/app/data
    depends_on:
      - ollama

volumes:
  ollama_data:
DOCKEREOF

# Replace placeholder with actual image URI
sudo sed -i "s|__ECR_IMAGE_URI__|__ECR_REGISTRY__/shoppollama:__IMAGE_TAG__|g" docker-compose.yml

# Clean data directory
sudo rm -rf data/*

# Start services
sudo /usr/local/bin/docker-compose up -d shoppollama

# Wait for container to be up
sleep 10

# Create database
sudo docker exec shoppollama-shoppollama-1 bin/shoppollama eval "Shoppollama.Repo.__adapter__().storage_up(Shoppollama.Repo.config())"

# Run migrations
sudo docker exec shoppollama-shoppollama-1 bin/shoppollama eval "Ecto.Migrator.run(Shoppollama.Repo, all, [log: :info])"

# Restart to ensure clean start
sudo /usr/local/bin/docker-compose restart shoppollama

# Start ollama
sudo /usr/local/bin/docker-compose up -d ollama

# Wait for ollama to start
sleep 30

# Pull a model
sudo docker exec shoppollama-ollama-1 ollama pull llama2

echo "✅ Deployment updated successfully!"
EOF

# Replace placeholders
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP "sudo sed -i 's|__ECR_REGISTRY__|$ECR_REGISTRY|g' /var/www/shoppollama/docker-compose.yml"
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP "sudo sed -i 's|__IMAGE_TAG__|$IMAGE_TAG|g' /var/www/shoppollama/docker-compose.yml"

echo ""
echo "✅ Redeployment complete!"
echo "🌐 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Ollama API: http://$PUBLIC_IP:11434"
echo ""
echo "⚠️  Note: It may take 2-3 minutes for everything to start."
echo ""
