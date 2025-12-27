#!/bin/bash

# Configuration
AWS_REGION="us-east-1"
ECR_REGISTRY="279714322890.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="shoppollama"
IMAGE_TAG="latest"
INSTANCE_NAME="shoppollama-final"
KEY_NAME="shoppollama-key"

echo "🚀 Deploying to EC2 instance..."

# Create user data script
cat > user-data-final.sh << 'EOF'
#!/bin/bash
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create run script
cat > run.sh << 'RUNEOF'
#!/bin/bash

# Generate secret
SECRET_KEY_BASE=$(openssl rand -base64 64)

# Run container
docker run -d \
  --name shoppollama \
  -p 4000:4000 \
  -v /var/www/shoppollama/data:/app/data \
  -e PORT=4000 \
  -e MIX_ENV=prod \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e DATABASE_PATH=/app/data/shoppollama.db \
  -e LIVE_VIEW_SIGNING_SALT="$SECRET_KEY_BASE" \
  279714322890.dkr.ecr.us-east-1.amazonaws.com/shoppollama:latest

echo "✅ Application started!"
RUNEOF

chmod +x run.sh
./run.sh
EOF

# Get latest Amazon Linux 2 ARM64 AMI
AMI_ID=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-hvm-*-arm64-gp2" "Name=virtualization-type,Values=hvm" --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" --output text)

# Create EC2 instance
echo "🔧 Creating EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t4g.medium \
  --key-name $KEY_NAME \
  --security-group-ids sg-0073136b6b0e38724 \
  --subnet-id subnet-099485b1570792810 \
  --user-data file://user-data-final.sh \
  --iam-instance-profile Name=shoppollama-instance-profile-b83d4dd \
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
rm -f user-data-final.sh
