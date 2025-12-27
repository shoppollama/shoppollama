#!/bin/bash

# Configuration
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="local-$(date +%Y%m%d-%H%M%S)"
INSTANCE_NAME="shoppollama-single"
KEY_NAME="shoppollama-key"

echo "🚀 Starting direct EC2 deployment..."

# Build Docker image
echo "📦 Building Docker image..."
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .

# Push to ECR
echo "📤 Pushing to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

# Create user data script
cat > user-data.sh << 'EOF'
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

# Create docker-compose.yml
cat > docker-compose.yml << 'DOCKEREOF'
version: '3.8'
services:
  shoppollama:
    image: __ECR_IMAGE_URI__
    ports:
      - "4000:4000"
    restart: unless-stopped
    environment:
      - PORT=4000
      - MIX_ENV=prod
      - DATABASE_PATH=/app/shoppollama.db
    volumes:
      - ./data:/app/data
DOCKEREOF

# Create startup script
cat > start.sh << 'STARTEOF'
#!/bin/bash
cd /var/www/shoppollama

# Create data directory
mkdir -p data

# Login to ECR and pull the image
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin __ECR_REGISTRY__

docker-compose down
docker-compose up -d

echo "✅ Application deployed!"
STARTEOF

chmod +x start.sh
./start.sh
EOF

# Replace placeholder with actual image URI
sed -i.bak "s|__ECR_IMAGE_URI__|$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG|g" user-data.sh
sed -i.bak "s|__ECR_REGISTRY__|$ECR_REGISTRY|g" user-data.sh

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)

# Get existing security group and instance profile
SG_ID="sg-0073136b6b0e38724"  # shoppollama-ec2-sg
PROFILE_NAME="shoppollama-instance-profile-b83d4dd"  # Use existing profile

# Create EC2 instance
echo "🔧 Creating EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --subnet-id subnet-099485b1570792810 \
  --user-data file://user-data.sh \
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
echo ""
echo "⚠️  Note: It may take 2-3 minutes for the application to start."
echo ""

# Cleanup
rm -f user-data.sh
