#!/bin/bash

# Configuration
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="t4g-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-t4g-large"
KEY_NAME="shoppollama-key"

echo "🚀 Starting EC2 deployment for t4g.large instance..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Create user data script
cat > user-data-t4g.sh << 'EOF'
#!/bin/bash
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create docker-compose.yml with both app and Ollama
cat > docker-compose.yml << 'DOCKEREOF'
version: '3.8'
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
      - PHX_SERVER=true
      - PHX_HOST=__PUBLIC_IP__
      - DATABASE_PATH=/app/shoppollama.db
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_TIMEOUT=180000
      - SECRET_KEY_BASE=__SECRET_KEY_BASE__
      - STRIPE_SECRET_KEY=__STRIPE_SECRET_KEY__
    volumes:
      - ./data:/app/data
      - ./shoppollama.db:/app/shoppollama.db
    depends_on:
      - ollama

volumes:
  ollama_data:
DOCKEREOF

# Create startup script
cat > start.sh << 'STARTEOF'
#!/bin/bash
cd /var/www/shoppollama

# Create data directory
mkdir -p data

# Login to ECR and pull the image
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin __ECR_REGISTRY__

# Pull and start services
docker-compose down
docker-compose pull
docker-compose up -d

# Wait for Ollama to start
echo "⏳ Waiting for Ollama to start..."
sleep 30

# Pull a model (you can change this to your preferred model)
docker-compose exec ollama ollama pull qwen2:1.5b

echo "✅ Application and Ollama deployed!"
echo "🔗 App URL: http://localhost:4000"
echo "🤖 Ollama API: http://localhost:11434"
STARTEOF

chmod +x start.sh
./start.sh
EOF

# Generate a secret key base
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

# Get Stripe key from environment
STRIPE_KEY="${STRIPE_SECRET_KEY:?STRIPE_SECRET_KEY environment variable is required}"

# Replace placeholders with actual values
sed -i.bak "s|__ECR_IMAGE_URI__|$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG|g" user-data-t4g.sh
sed -i.bak "s|__ECR_REGISTRY__|$ECR_REGISTRY|g" user-data-t4g.sh
sed -i.bak "s|__SECRET_KEY_BASE__|$SECRET_KEY_BASE|g" user-data-t4g.sh
sed -i.bak "s|__STRIPE_SECRET_KEY__|$STRIPE_KEY|g" user-data-t4g.sh

# Get latest Amazon Linux 2 ARM64 AMI (for t4g.large)
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-arm64-gp2" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)

# Get existing security group and instance profile
SG_ID="sg-0073136b6b0e38724"  # shoppollama-ec2-sg
PROFILE_NAME="shoppollama-instance-profile-b83d4dd"  # Use existing profile

# Create EC2 instance with t4g.large (2 vCPU, 8GB RAM, 50GB storage)
echo "🔧 Creating EC2 instance t4g.large with 50GB storage..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t4g.large \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --subnet-id subnet-099485b1570792810 \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
  --user-data file://user-data-t4g.sh \
  --iam-instance-profile Name=$PROFILE_NAME \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Allocate Elastic IP
echo "🌐 Allocating Elastic IP..."
EIP_ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query "AllocationId" --output text)

# Associate EIP with instance
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOCATION_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "✅ Deployment complete!"
echo "📍 Instance ID: $INSTANCE_ID"
echo "🌐 Public IP: $PUBLIC_IP"
echo "🔗 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Ollama API: http://$PUBLIC_IP:11434"
echo ""
echo "⚠️  Note: It may take 3-5 minutes for everything to start."
echo "📝 The instance will automatically pull the qwen2:1.5b model."
echo ""
echo "🔧 Updating PHX_HOST with public IP..."

# Wait for SSH to be available
sleep 60

# Update PHX_HOST in docker-compose.yml on the instance
ssh -i shoppollama-key.pem -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP "cd /var/www/shoppollama && sudo sed -i 's|PHX_HOST=__PUBLIC_IP__|PHX_HOST=$PUBLIC_IP|g' docker-compose.yml && sudo sed -i 's|./shoppollama.db:/app/shoppollama.db|./db:/app/db|g' docker-compose.yml && sudo sed -i 's|DATABASE_PATH=/app/shoppollama.db|DATABASE_PATH=/app/db/shoppollama.db|g' docker-compose.yml && sudo mkdir -p db && sudo chmod 777 db && docker-compose down && docker-compose up -d"

echo "✅ PHX_HOST updated to $PUBLIC_IP"

# Cleanup
rm -f user-data-t4g.sh user-data-t4g.sh.bak
