import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";

const config = new pulumi.Config();
const instanceType = config.get("instanceType") || "t3.medium";
const environment = config.get("environment") || "prod";
const ecrImageUri = config.require("ecrImageUri");

// Use existing EC2 Key Pair for SSH access
const keyPair = new aws.ec2.KeyPair("shoppollama-key", {
    keyName: "shoppollama-key",
    publicKey: `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZEg3E41liKQGzWuP9j6SVXHeB6XMBKv8uC8+ma5Wld1iikboGDoVUY7BFw/Rp9SKdYiPOGwgH28HkcZRSZkKKn2sIIOluj2eRnn7s2AZaNiUS9jblR3Xg4VKfhYPzP/m40s18n+wO4fGEEsqE6KDx7w9fsOUAHo8iMBajD5JbGMUuDmrV1nwnRsnVJ21+xH6fVChBgzQKpvI6b7cjDXhzM9xPreqz1PqFV8+XLxDF0MBtFm9GKNcB6wiPeCSOj+MnG8eI919lHsW3OtRjNeTk45b1K/uaXIwFgEm/qBnhfIGRh1Wk46CYERIqECHFJ6bFPmnqF3O1nNChRiC8C2mVe9FWwdTE1/riNs+goMNtebb1s1lgkXq7hgRBUiqGoZp/wtRfz76fsAa+LBiD8xTJReiW8mJsh4YMoU/02f/Q8gohy6JZ+0fRr0SacMXcCLAydg5ZAVJXTPJB/M32mAptubJzeL3VvePu5kS4YyHmJXfQ1AbXBAWK8Va5IeF3L0INH2SKXALVc+kAyBNqXmMY7dXRY7hCvHTy2goFquDKDa3mhUi8H1NqjrRNJN0dM3H/2VXEqEUGKYXpE+1WwwuN7F/+obM3TCaCZD9yCHcAuMXYUtd9GwB7B7dgnBAuQHfVxhACotARBmb/HwG9VVedzpOBwuOoy/kDXUaeNteksQ== shoppollama@pulumi`
}, { import: "shoppollama-key" });

// Create S3 bucket for Mix releases
const releasesBucket = new aws.s3.Bucket("shoppollama-releases", {
    bucket: pulumi.interpolate`shoppollama-releases-${environment}-${pulumi.getStack()}`,
    tags: {
        Name: "shoppollama-releases",
        Environment: environment,
    },
});

// Use existing VPC
const vpc = aws.ec2.getVpc({
    id: "vpc-083d38d951d2954e8",
});

// Create Internet Gateway
const internetGateway = new aws.ec2.InternetGateway("shoppollama-igw", {
    vpcId: vpc.then(v => v.id),
    tags: {
        Name: "shoppollama-igw",
        Environment: environment,
    },
});

// Create Public Subnets
const publicSubnet1 = aws.ec2.getSubnet({
    id: "subnet-099485b1570792810",
});

const publicSubnet2 = aws.ec2.getSubnet({
    id: "subnet-0f4bd71ebf91a16c5",
});

// Create Route Table
const routeTable = new aws.ec2.RouteTable("shoppollama-rt", {
    vpcId: vpc.then(v => v.id),
    routes: [{
        cidrBlock: "0.0.0.0/0",
        gatewayId: internetGateway.id,
    }],
    tags: {
        Name: "shoppollama-rt",
        Environment: environment,
    },
});

// Associate Route Table with Subnets
const routeTableAssociation1 = new aws.ec2.RouteTableAssociation("shoppollama-rta-1", {
    subnetId: publicSubnet1.then(s => s.id),
    routeTableId: routeTable.id,
});

const routeTableAssociation2 = new aws.ec2.RouteTableAssociation("shoppollama-rta-2", {
    subnetId: publicSubnet2.then(s => s.id),
    routeTableId: routeTable.id,
});

// Create Security Group for ALB (declared first to avoid forward reference)
const albSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-alb-sg", {
    vpcId: vpc.then(v => v.id),
    ingress: [{
        protocol: "tcp",
        fromPort: 80,
        toPort: 80,
        cidrBlocks: ["0.0.0.0/0"],
    }],
    egress: [{
        protocol: "-1",
        fromPort: 0,
        toPort: 0,
        cidrBlocks: ["0.0.0.0/0"],
    }],
    tags: {
        Name: "shoppollama-alb-sg",
        Environment: environment,
    },
});

// Create IAM role for EC2 instances
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
    tags: {
        Name: "shoppollama-ec2-role",
        Environment: environment,
    },
});

// Create S3 policy for releases bucket
const s3Policy = new aws.iam.RolePolicy("shoppollama-s3-policy", {
    role: ec2Role.id,
    policy: pulumi.all([releasesBucket.arn]).apply(([arn]) => JSON.stringify({
        Version: "2012-10-17",
        Statement: [
            {
                Effect: "Allow",
                Action: [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                Resource: [
                    arn,
                    `${arn}/*`,
                ],
            },
        ],
    })),
});

// Create Instance Profile
const instanceProfile = new aws.iam.InstanceProfile("shoppollama-instance-profile", {
    role: ec2Role.name,
});

// Create Security Group for Build Server
const buildSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-build-sg", {
    vpcId: vpc.then(vpc => vpc.id),
    ingress: [
        {
            protocol: "tcp",
            fromPort: 22,
            toPort: 22,
            cidrBlocks: ["0.0.0.0/0"], // SSH access for GitHub Actions
        },
    ],
    egress: [{
        protocol: "-1",
        fromPort: 0,
        toPort: 0,
        cidrBlocks: ["0.0.0.0/0"],
    }],
    tags: {
        Name: "shoppollama-build-sg",
        Environment: environment,
    },
});

// Build server user data script
const buildServerUserData = `#!/bin/bash
yum update -y

# Install AWS CLI
yum install -y aws-cli

# Install Elixir/Erlang
yum install -y wget git unzip openssl-devel ncurses-devel gcc gcc-c++ make
cd /tmp
wget https://packages.erlang-solutions.com/erlang-solutions-2.0-1.noarch.rpm
rpm -Uvh erlang-solutions-2.0-1.noarch.rpm
yum install -y erlang elixir

# Install Node.js for asset compilation
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Install build tools
yum install -y sqlite sqlite-devel

# Create app directory
mkdir -p /home/ec2-user/shoppollama
cd /home/ec2-user/shoppollama

# Create deployment script
cat > deploy.sh << EOF
#!/bin/bash
set -e

echo "🚀 Starting build process..."

# Get latest code
git pull origin main

# Install dependencies
mix deps.get --only-prod
mix compile

# Compile assets
mix assets.deploy

# Build release
mix release --overwrite

# Create release archive
cd _build/prod/rel
tar -czf shoppollama-release.tar.gz shoppollama/

# Upload to S3 with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
aws s3 cp shoppollama-release.tar.gz s3://shoppollama-releases-${environment}-\${STACK}/releases/shoppollama-\${TIMESTAMP}.tar.gz

# Update latest pointer
echo "\${TIMESTAMP}" | aws s3 cp - s3://shoppollama-releases-${environment}-\${STACK}/latest.txt

echo "✅ Build and upload complete! Release: shoppollama-\${TIMESTAMP}.tar.gz"
EOF

chmod +x deploy.sh

echo "✅ Build server ready!"
`;

// Create Build Server Instance
const buildInstance = new aws.ec2.Instance("shoppollama-build", {
    instanceType: "t3.medium",
    subnetId: publicSubnet1.id,
    ami: aws.ec2.getAmi({
        filters: [
            { name: "name", values: ["amzn2-ami-hvm-*-x86_64-gp2"] },
            { name: "virtualization-type", values: ["hvm"] },
        ],
        mostRecent: true,
    }).then((ami: aws.GetAmiResult) => ami.id),
    vpcSecurityGroupIds: [buildSecurityGroup.id],
    iamInstanceProfile: instanceProfile,
    userData: Buffer.from(buildServerUserData).toString("base64") as string,
    keyName: keyPair.keyName,
    tags: {
        Name: "shoppollama-build",
        Environment: environment,
    },
});

// Create Security Group for EC2
const ec2SecurityGroup = new aws.ec2.SecurityGroup("shoppollama-ec2-sg", {
    vpcId: vpc.then(vpc => vpc.id),
    ingress: [
        {
            protocol: "tcp",
            fromPort: 4000,
            toPort: 4000,
            securityGroups: [albSecurityGroup.id], // Allow health check traffic from ALB
        },
        {
            protocol: "tcp",
            fromPort: 22,
            toPort: 22,
            securityGroups: [buildSecurityGroup.id], // Allow SSH from build server
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

// User data script for EC2 instance
const userData = `#!/bin/bash
yum update -y

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

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

# Run the application
./start.sh`;

// Create EC2 Launch Template
const launchTemplate = new aws.ec2.LaunchTemplate("shoppollama-launch-template", {
    namePrefix: "shoppollama",
    imageId: aws.getAmi({
        filters: [
            { name: "name", values: ["amzn2-ami-hvm-*-x86_64-gp2"] },
            { name: "virtualization-type", values: ["hvm"] },
        ],
        mostRecent: true,
    }).then((ami: aws.GetAmiResult) => ami.id),
    instanceType: instanceType,
    userData: Buffer.from(userData).toString("base64") as string,
    vpcSecurityGroupIds: [ec2SecurityGroup.id],
    iamInstanceProfile: {
        name: instanceProfile.name,
    },
    tags: {
        Name: "shoppollama",
        Environment: environment,
    },
});

// Create Application Load Balancer
const alb = new aws.lb.LoadBalancer("shoppollama-alb", {
    internal: false,
    loadBalancerType: "application",
    securityGroups: [albSecurityGroup.id],
    subnetIds: [publicSubnet1.then(s => s.id), publicSubnet2.then(s => s.id)],
    tags: {
        Name: "shoppollama-alb",
        Environment: environment,
    },
});

// Create Target Group
const targetGroup = new aws.lb.TargetGroup("shoppollama-tg", {
    port: 4000,
    protocol: "HTTP",
    vpcId: vpc.then(vpc => vpc.id),
    targetType: "instance",
    healthCheck: {
        path: "/",
        interval: 30,
        timeout: 5,
        healthyThreshold: 2,
        unhealthyThreshold: 2,
        matcher: "200",
    },
    tags: {
        Name: "shoppollama-tg",
        Environment: environment,
    },
});

// Create Listener
const listener = new aws.lb.Listener("shoppollama-listener", {
    loadBalancerArn: alb.arn,
    port: 80,
    protocol: "HTTP",
    defaultActions: [{
        type: "forward",
        targetGroupArn: targetGroup.arn,
    }],
});

// Create Auto Scaling Group
const asg = new aws.autoscaling.Group("shoppollama-asg", {
    launchTemplate: {
        id: launchTemplate.id,
        version: launchTemplate.latestVersion.apply(v => v.toString()),
    },
    vpcZoneIdentifier: [publicSubnet1.then(s => s.id), publicSubnet2.then(s => s.id)],
    targetGroupArns: [targetGroup.arn],
    minSize: 1,
    maxSize: 3,
    desiredCapacity: 1,
    healthCheckType: "EC2",
    healthCheckGracePeriod: 300,
    tags: [{
        key: "Name",
        value: "shoppollama",
        propagateAtLaunch: true,
    }, {
        key: "Environment",
        value: environment,
        propagateAtLaunch: true,
    }],
});

// Export outputs
export const loadBalancerDns = alb.dnsName;
export const loadBalancerUrl = pulumi.interpolate`http://${alb.dnsName}`;
export const vpcId = vpc.then(vpc => vpc.id);
export const instanceProfileArn = instanceProfile.arn;
export const buildServerPublicIp = buildInstance.publicIp;
export const buildServerPublicDns = buildInstance.publicDns;
export const releasesBucketName = releasesBucket.bucket;
export const releasesBucketArn = releasesBucket.arn;
