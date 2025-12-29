#!/bin/bash

# Build and deploy with correct llama2:latest model

# Configuration
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="t4g-llama2-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-t4g-large-llama2"
KEY_NAME="shoppollama-key"
PUBLIC_IP="3.239.18.130"

echo "🚀 Building and deploying with llama2:latest model..."

# First, update the model references in the code
echo "📝 Updating model references in code..."

# Update OllamaClient default model
sed -i.bak 's/@default_model "llama3.2:3b"/@default_model "llama2:latest"/' lib/shoppollama/ollama_client.ex

# Update chat_live.ex default model
sed -i.bak 's/assign(:selected_model, "llama3.2:3b")/assign(:selected_model, "llama2:latest")/' lib/shoppollama_web/live/chat_live.ex

# Update TextAnalyzer model references
sed -i.bak 's/model: "llama3.2:3b"/model: "llama2:latest"/g' lib/shoppollama/text_analyzer.ex

# Update generate_ai_response function
sed -i.bak 's/running on #{model}/running on llama2:latest/' lib/shoppollama_web/live/chat_live.ex

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Deploy to existing instance
echo "🔧 Updating deployment on existing instance..."

ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP << 'EOF'
cd /var/www/shoppollama
sudo /usr/local/bin/docker-compose down

# Update docker-compose.yml with new image
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
      - SECRET_KEY_BASE=P+P5q/qCLUkr1SEAEk9U1+qg8aZJZZrFNBgHdwRlHfUn6IusHnQcL3N9vR2Ks8mX5yF7jH4gW3eB1zA6dC8vE0fG2hI4jK6lM8nO0pQ2rS4tU6vW8xY0z
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

# Replace placeholder
sudo sed -i "s|__ECR_IMAGE_URI__|$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG|g" docker-compose.yml

# Start services
sudo /usr/local/bin/docker-compose up -d

echo "✅ Deployment updated!"
EOF

echo ""
echo "✅ Deployment complete!"
echo "🌐 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Using model: llama2:latest"
echo ""

# Restore original files
echo "🔄 Restoring original files..."
mv lib/shoppollama/ollama_client.ex.bak lib/shoppollama/ollama_client.ex
mv lib/shoppollama_web/live/chat_live.ex.bak lib/shoppollama_web/live/chat_live.ex
mv lib/shoppollama/text_analyzer.ex.bak lib/shoppollama/text_analyzer.ex
