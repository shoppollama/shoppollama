#!/bin/bash

# Update model references in the codebase from llama3.2:3b to llama2:latest

echo "🔄 Updating model references..."

# Connect to the instance and update the code
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.239.18.130 << 'EOF'

# First, let's find where the model is referenced
echo "Finding model references..."
cd /var/www/shoppollama

# Since the code is baked into the Docker image, we need to rebuild with correct model
# Let's create a temporary fix by setting environment variable
sudo /usr/local/bin/docker-compose down

# Update docker-compose.yml to include model environment variable
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
    image: 279714322890.dkr.ecr.us-east-1.amazonaws.com/shoppollama:t4g-20251227-173952
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
      - DEFAULT_MODEL=llama2:latest
    volumes:
      - ./data:/app/data
    depends_on:
      - ollama

volumes:
  ollama_data:
DOCKEREOF

# Start the services
sudo /usr/local/bin/docker-compose up -d

echo "✅ Services updated with llama2:latest model"
EOF

echo ""
echo "✅ Model update complete!"
echo "🌐 Application URL: http://3.239.18.130:4000"
echo ""
