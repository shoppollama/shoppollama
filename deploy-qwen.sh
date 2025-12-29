#!/bin/bash

# Update deployment to use qwen:0.5b model

echo "🔄 Updating to use qwen:0.5b model..."

# Build new image with updated model
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="t4g-qwen-$(date +%Y%m%d-%H%M%S)"
PUBLIC_IP="3.239.18.130"

# Update the model references in the code
echo "📝 Updating model references to qwen:0.5b..."

# Create temporary modified files
cp lib/shoppollama/ollama_client.ex lib/shoppollama/ollama_client.ex.bak2
cp lib/shoppollama_web/live/chat_live.ex lib/shoppollama_web/live/chat_live.ex.bak2
cp lib/shoppollama/text_analyzer.ex lib/shoppollama/text_analyzer.ex.bak2

# Update OllamaClient default model
sed -i 's/@default_model "llama2:latest"/@default_model "qwen:0.5b"/' lib/shoppollama/ollama_client.ex

# Update chat_live.ex default model
sed -i 's/assign(:selected_model, "llama2:latest")/assign(:selected_model, "qwen:0.5b")/' lib/shoppollama_web/live/chat_live.ex

# Update TextAnalyzer model references
sed -i 's/model: "llama2:latest"/model: "qwen:0.5b"/g' lib/shoppollama/text_analyzer.ex

# Update generate_ai_response function
sed -i 's/running on llama2:latest/running on qwen:0.5b/' lib/shoppollama_web/live/chat_live.ex

# Build Docker image
echo "📦 Building Docker image with qwen:0.5b..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Deploy to instance
echo "🔧 Deploying to instance..."
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP << 'EOF'
cd /var/www/shoppollama
sudo /usr/local/bin/docker-compose down

# Update docker-compose.yml
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
      - OLLAMA_LOAD_TIMEOUT=5m
      - OLLAMA_REQUEST_TIMEOUT=2m
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

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
      - OLLAMA_TIMEOUT=60000
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

echo "✅ Deployment updated with qwen:0.5b"
EOF

echo ""
echo "✅ Deployment complete!"
echo "🌐 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Using model: qwen:0.5b (smaller, faster model)"
echo ""

# Restore original files
echo "🔄 Restoring original files..."
mv lib/shoppollama/ollama_client.ex.bak2 lib/shoppollama/ollama_client.ex
mv lib/shoppollama_web/live/chat_live.ex.bak2 lib/shoppollama_web/live/chat_live.ex
mv lib/shoppollama/text_analyzer.ex.bak2 lib/shoppollama/text_analyzer.ex
