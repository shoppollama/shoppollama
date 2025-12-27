import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

const config = new pulumi.Config();
const environment = config.get("environment") || "prod";
const ecrImageUri = config.require("ecrImageUri");

// Use existing VPC
const vpc = aws.ec2.getVpc({
    id: "vpc-083d38d951d2954e8",
});

// Use existing Internet Gateway
const internetGateway = aws.ec2.getInternetGateway({
    id: "igw-0a012057cc87d129c",
});

// Use existing subnets
const publicSubnet1 = aws.ec2.getSubnet({
    id: "subnet-099485b1570792810",
});

const publicSubnet2 = aws.ec2.getSubnet({
    id: "subnet-0f4bd71ebf91a16c5",
});

// Use existing route table
const routeTable = aws.ec2.getRouteTable({
    id: "rtb-06a4a2bdb42621f46",
});

// Use existing route table associations - skip as they're already associated

// Create Security Group for EC2
const ec2SecurityGroup = new aws.ec2.SecurityGroup("shoppollama-ec2-sg", {
    vpcId: vpc.then(v => v.id),
    ingress: [
        {
            protocol: "tcp",
            fromPort: 4000,
            toPort: 4000,
            cidrBlocks: ["0.0.0.0/0"], // Allow from anywhere
        },
        {
            protocol: "tcp",
            fromPort: 22,
            toPort: 22,
            cidrBlocks: ["0.0.0.0/0"], // SSH access
        },
        {
            protocol: "tcp",
            fromPort: 80,
            toPort: 80,
            cidrBlocks: ["0.0.0.0/0"], // HTTP for ALB
        },
    ],
    egress: [{
        protocol: "-1",
        fromPort: 0,
        toPort: 0,
        cidrBlocks: ["0.0.0.0/0"],
    }],
    tags: {
        Name: "shoppollama-ec2-sg",
        Environment: environment,
    },
});

// Create IAM role for EC2
const ec2Role = new aws.iam.Role("shoppollama-ec2-role", {
    assumeRolePolicy: JSON.stringify({
        Version: "2012-10-17",
        Statement: [{
            Action: "sts:AssumeRole",
            Effect: "Allow",
            Principal: {
                Service: "ec2.amazonaws.com",
            },
        }],
    }),
});

// Attach SSM policy for session manager access
const ssmPolicy = new aws.iam.RolePolicyAttachment("shoppollama-ssm-policy", {
    role: ec2Role.name,
    policyArn: aws.iam.ManagedPolicies.AmazonSSMManagedInstanceCore,
});

// Attach ECR read-only policy for pulling images
const ecrPolicy = new aws.iam.RolePolicyAttachment("shoppollama-ecr-policy", {
    role: ec2Role.name,
    policyArn: aws.iam.ManagedPolicies.AmazonEC2ContainerRegistryReadOnly,
});

// Create Instance Profile
const instanceProfile = new aws.iam.InstanceProfile("shoppollama-instance-profile", {
    role: ec2Role.name,
});

// Use existing EC2 Key Pair for SSH access
const keyPair = aws.ec2.getKeyPair({
    keyName: "shoppollama-key",
});

// User data script for EC2 instance
const userData = `#!/bin/bash
yum update -y

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  shoppollama:
    image: ${ecrImageUri}
    ports:
      - "4000:4000"
    restart: unless-stopped
    environment:
      - PORT=4000
      - MIX_ENV=prod
      - DATABASE_PATH=/app/shoppollama.db
    volumes:
      - ./data:/app/data
EOF

# Create startup script
cat > start.sh << 'EOF'
#!/bin/bash
cd /var/www/shoppollama

# Create data directory
mkdir -p data

# Login to ECR and pull the image
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ecrImageUri.split('/')[0]}

docker-compose down
docker-compose up -d
EOF

chmod +x start.sh
./start.sh

echo "✅ Application deployed!"
`;

// Create single EC2 instance
const instance = new aws.ec2.Instance("shoppollama-instance", {
    instanceType: "t3.medium",
    subnetId: publicSubnet1.then(s => s.id),
    ami: aws.ec2.getAmi({
        filters: [
            { name: "name", values: ["amzn2-ami-hvm-*-x86_64-gp2"] },
            { name: "virtualization-type", values: ["hvm"] },
        ],
        mostRecent: true,
    }).then((ami: aws.GetAmiResult) => ami.id),
    vpcSecurityGroupIds: [ec2SecurityGroup.id],
    iamInstanceProfile: instanceProfile,
    userData: Buffer.from(userData).toString("base64") as string,
    keyName: keyPair.keyName,
    tags: {
        Name: "shoppollama",
        Environment: environment,
    },
});

// Create Elastic IP
const eip = new aws.ec2.Eip("shoppollama-eip", {
    instance: instance.id,
    vpc: true,
    tags: {
        Name: "shoppollama-eip",
        Environment: environment,
    },
});

// Export outputs
export const instancePublicIp = instance.publicIp;
export const instancePublicDns = instance.publicDns;
export const instanceId = instance.id;
export const applicationUrl = pulumi.interpolate`http://${instance.publicIp}:4000`;
export const vpcId = vpc.then(v => v.id);
export const instanceProfileArn = instanceProfile.arn;
