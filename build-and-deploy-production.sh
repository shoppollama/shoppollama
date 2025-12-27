#!/bin/bash

# Build and deploy a new Docker image with all fixes for production

echo "Building production Docker image with Ollama integration..."

# First, let's create a Dockerfile if it doesn't exist
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 << 'EOF'
# Check if we have the source code
if [ ! -d "/home/ec2-user/shoppollama-source" ]; then
    echo "Cloning fresh source code..."
    git clone https://github.com/yourusername/shoppollama.git /home/ec2-user/shoppollama-source
fi

cd /home/ec2-user/shoppollama-source
git pull origin main

# Create Dockerfile if it doesn't exist
cat > Dockerfile << 'DOCKERFILE'
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base npm git python3

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set environment for prod
ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs ./
RUN mix deps.compile

# Build assets
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm --prefix ./assets ci
RUN mix assets.deploy

# Compile the application
COPY lib ./
RUN mix compile

# Prepare release
COPY config/runtime.exs ./
RUN mix release

# Prepare a new runner image
FROM alpine:3.18 AS runner

# Install openssl
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=builder /app/_build/prod/rel/shoppollama ./

ENV HOME=/app

CMD ["bin/shoppollama", "start"]
DOCKERFILE

# Build the new image
sudo docker build -t shoppollama:production .

echo "Built new production image!"
EOF

echo "Now deploying the new image..."

ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@3.238.183.127 << 'EOF'
cd /var/www/shoppollama

# Stop existing containers
sudo docker-compose down

# Update docker-compose.yml to use the new image
sudo sed -i 's|279714322890.dkr.ecr.us-east-1.amazonaws.com/shoppollama:local-20251227-2055|shoppollama:production|' docker-compose.yml

# Start with the new image
sudo /usr/local/bin/docker-compose up -d

echo "Deployment complete!"
EOF
