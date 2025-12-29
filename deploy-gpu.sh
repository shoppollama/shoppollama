#!/bin/bash

# GPU Deployment - g4dn.xlarge (4 vCPU, 16GB RAM, NVIDIA T4 GPU)
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="gpu-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-gpu"
KEY_NAME="shoppollama-key"

echo "🚀 Starting GPU deployment (g4dn.xlarge with NVIDIA T4)..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Generate secrets
SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')
STRIPE_KEY="${STRIPE_SECRET_KEY:?STRIPE_SECRET_KEY environment variable is required}"

# Create user data script for GPU instance
cat > user-data-gpu.sh << 'EOF'
#!/bin/bash
set -e

# Update system
yum update -y

# Install Docker
amazon-linux-extras install docker -y
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install NVIDIA drivers and container toolkit
yum install -y gcc kernel-devel-$(uname -r)
amazon-linux-extras install epel -y
yum install -y nvidia-driver-latest-dkms

# Install nvidia-container-toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | tee /etc/yum.repos.d/nvidia-container-toolkit.repo
yum install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create docker-compose.yml with GPU support
cat > docker-compose.yml << 'DOCKEREOF'
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
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  shoppollama:
    image: __ECR_IMAGE_URI__
    ports:
      - "4000:4000"
    restart: unless-stopped
    environment:
      - PORT=4000
      - MIX_ENV=prod
      - PHX_SERVER=true
      - PHX_HOST=localhost
      - DATABASE_PATH=/app/data/shoppollama.db
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_TIMEOUT=60000
      - SECRET_KEY_BASE=__SECRET_KEY_BASE__
      - STRIPE_SECRET_KEY=__STRIPE_KEY__
    volumes:
      - ./data:/app/data
    depends_on:
      - ollama

volumes:
  ollama_data:
DOCKEREOF

# Create data directory with proper permissions
mkdir -p data
chmod 777 data

# Create startup script
cat > start.sh << 'STARTEOF'
#!/bin/bash
cd /var/www/shoppollama

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin __ECR_REGISTRY__

# Pull and start services
docker-compose down 2>/dev/null || true
docker-compose pull
docker-compose up -d

# Wait for Ollama to start
echo "⏳ Waiting for Ollama to start..."
sleep 20

# Pull the model
echo "📥 Pulling llama3.2:3b model..."
docker-compose exec -T ollama ollama pull llama3.2:3b

echo "✅ GPU deployment complete!"
echo "🔗 App URL: http://localhost:4000"
echo "🤖 Ollama API: http://localhost:11434"
STARTEOF

chmod +x start.sh
./start.sh
EOF

# Replace placeholders
sed -i.bak "s|__ECR_IMAGE_URI__|$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG|g" user-data-gpu.sh
sed -i.bak "s|__ECR_REGISTRY__|$ECR_REGISTRY|g" user-data-gpu.sh
sed -i.bak "s|__SECRET_KEY_BASE__|$SECRET_KEY_BASE|g" user-data-gpu.sh
sed -i.bak "s|__STRIPE_KEY__|$STRIPE_KEY|g" user-data-gpu.sh

# Get Amazon Linux 2 x86_64 AMI (for GPU instances)
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)

# Use existing security group and instance profile
SG_ID="sg-0073136b6b0e38724"
PROFILE_NAME="shoppollama-instance-profile-b83d4dd"

echo "🔧 Creating g4dn.xlarge GPU instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type g4dn.xlarge \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --subnet-id subnet-099485b1570792810 \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":100,"VolumeType":"gp3"}}]' \
  --user-data file://user-data-gpu.sh \
  --iam-instance-profile Name=$PROFILE_NAME \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP (use existing EIP or instance IP)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "✅ GPU Deployment initiated!"
echo "📍 Instance ID: $INSTANCE_ID"
echo "🌐 Public IP: $PUBLIC_IP"
echo "🔗 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Ollama API: http://$PUBLIC_IP:11434"
echo ""
echo "⚠️  GPU setup takes 5-10 minutes (NVIDIA drivers + model download)"
echo "💡 Ollama will be ~10x faster with GPU acceleration!"
echo ""

# Cleanup
rm -f user-data-gpu.sh user-data-gpu.sh.bak
