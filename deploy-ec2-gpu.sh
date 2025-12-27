#!/bin/bash

# Configuration for GPU-enabled EC2 instance
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="local-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-gpu"
KEY_NAME="shoppollama-key"

echo "🚀 Starting EC2 deployment with GPU support for Ollama..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Create user data script with GPU support
cat > user-data-gpu.sh << 'EOF'
#!/bin/bash
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

yum install -y nvidia-container-toolkit
systemctl restart docker

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create docker-compose.yml with GPU support
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
      - DATABASE_PATH=/app/shoppollama.db
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - ./data:/app/data
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
docker-compose exec ollama ollama pull llama2
# For better performance, you might want:
# docker-compose exec ollama ollama pull codellama
# docker-compose exec ollama ollama pull mistral

echo "✅ Application and Ollama deployed with GPU support!"
echo "🔗 App URL: http://localhost:4000"
echo "🤖 Ollama API: http://localhost:11434"
echo "🎮 GPU Status: nvidia-smi"
STARTEOF

chmod +x start.sh
./start.sh
EOF

# Replace placeholder with actual image URI
sed -i.bak "s|__ECR_IMAGE_URI__|$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG|g" user-data-gpu.sh
sed -i.bak "s|__ECR_REGISTRY__|$ECR_REGISTRY|g" user-data-gpu.sh

# Get latest Amazon Linux 2 AMI with GPU support
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)

# Get existing security group and instance profile
SG_ID="sg-0073136b6b0e38724"  # shoppollama-ec2-sg
PROFILE_NAME="shoppollama-instance-profile-b83d4dd"  # Use existing profile

# Create EC2 instance with GPU (g4dn.xlarge) and bigger storage
echo "🔧 Creating GPU-enabled EC2 instance..."
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

# Allocate Elastic IP
echo "🌐 Allocating Elastic IP..."
EIP_ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query "AllocationId" --output text)

# Associate EIP with instance
aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOCATION_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo ""
echo "✅ GPU-enabled deployment complete!"
echo "📍 Instance ID: $INSTANCE_ID"
echo "🌐 Public IP: $PUBLIC_IP"
echo "🔗 Application URL: http://$PUBLIC_IP:4000"
echo "🤖 Ollama API: http://$PUBLIC_IP:11434"
echo "💰 Instance type: g4dn.xlarge (with NVIDIA T4 GPU)"
echo ""
echo "⚠️  Note: It may take 3-5 minutes for everything to start."
echo "📝 The instance will automatically pull the llama2 model."
echo "💡 To check GPU usage: ssh -i shoppollama-key.pem ec2-user@$PUBLIC_IP 'docker exec ollama nvidia-smi'"
echo ""

# Cleanup
rm -f user-data-gpu.sh
