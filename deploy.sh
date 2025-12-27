#!/bin/bash

# Deployment script for Shoppollama to AWS using Pulumi

set -e

echo "🚀 Deploying Shoppollama to AWS..."

# Check if Pulumi is installed
if ! command -v pulumi &> /dev/null; then
    echo "❌ Pulumi is not installed. Please install it first:"
    echo "   curl -fsSL https://get.pulumi.com | sh"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured or credentials are invalid."
    echo ""
    echo "To fix this issue:"
    echo "1. Get valid AWS credentials from AWS Console → IAM → Users → Your User → Security credentials"
    echo "2. Run: aws configure"
    echo "3. Enter your Access Key ID, Secret Access Key, region (us-east-1), and output format (json)"
    echo ""
    echo "Alternatively, edit ~/.aws/credentials directly:"
    echo "[default]"
    echo "aws_access_key_id = YOUR_ACCESS_KEY_ID"
    echo "aws_secret_access_key = YOUR_SECRET_ACCESS_KEY"
    echo ""
    echo "And ~/.aws/config:"
    echo "[default]"
    echo "region = us-east-1"
    echo "output = json"
    exit 1
fi

# Check for required IAM permissions
echo "🔐 Checking IAM permissions..."
REQUIRED_PERMISSIONS=(
    "iam:CreateRole"
    "iam:CreateInstanceProfile"
    "iam:AddRoleToInstanceProfile"
    "iam:PassRole"
    "ec2:CreateVpc"
    "ec2:CreateSubnet"
    "ec2:CreateSecurityGroup"
    "ec2:CreateLaunchTemplate"
    "ec2:CreateAutoScalingGroup"
    "elasticloadbalancing:CreateLoadBalancer"
)

for permission in "${REQUIRED_PERMISSIONS[@]}"; do
    if ! aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names $permission --resource-arn "*" | grep -q '"EvalDecision": "allowed"'; then
        echo "❌ Missing IAM permission: $permission"
        echo ""
        echo "Your AWS user needs the following permissions to deploy Shoppollama:"
        echo "- IAM permissions for roles and instance profiles"
        echo "- EC2 permissions for VPC, subnets, security groups, and instances"
        echo "- Elastic Load Balancing permissions"
        echo ""
        echo "To fix this:"
        echo "1. Go to AWS Console → IAM → Users → shoppollama"
        echo "2. Click 'Add permissions' → 'Attach existing policies directly'"
        echo "3. Attach the 'AdministratorAccess' policy (for testing)"
        echo "   OR create a custom policy with the required permissions"
        echo ""
        echo "For production, create a custom policy with minimum required permissions."
        exit 1
    fi
done

echo "✅ IAM permissions check passed"

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Select stack (default to dev)
STACK=${1:-dev}
echo "🔧 Using stack: $STACK"

# Create stack if it doesn't exist
if ! pulumi stack select $STACK 2>/dev/null; then
    echo "🆕 Creating new stack: $STACK"
    pulumi stack init $STACK
    if [ -f "Pulumi.$STACK.yaml" ]; then
        echo "📋 Using stack configuration: Pulumi.$STACK.yaml"
    fi
fi

# Build TypeScript
echo "🔨 Building TypeScript..."
npm run build

# Preview deployment
echo "👀 Previewing deployment..."
pulumi preview --stack $STACK

# Ask for confirmation
echo ""
read -p "🚀 Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Deploy
    echo "🚀 Deploying..."
    pulumi up --stack $STACK --yes
    
    # Get outputs
    echo ""
    echo "✅ Deployment complete!"
    echo "🌐 Load Balancer URL: $(pulumi stack output loadBalancerUrl --stack $STACK)"
    echo "🔍 VPC ID: $(pulumi stack output vpcId --stack $STACK)"
else
    echo "❌ Deployment cancelled."
    exit 1
fi
