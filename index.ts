import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as awsx from "@pulumi/awsx";

const config = new pulumi.Config();
const instanceType = config.get("instanceType") || "t3.medium";
const environment = config.get("environment") || "prod";

// Create VPC
const vpc = new aws.ec2.Vpc("shoppollama-vpc", {
    cidrBlock: "10.0.0.0/16",
    enableDnsHostnames: true,
    enableDnsSupport: true,
    tags: {
        Name: "shoppollama-vpc",
        Environment: environment,
    },
});

// Create Internet Gateway
const internetGateway = new aws.ec2.InternetGateway("shoppollama-igw", {
    vpcId: vpc.id,
    tags: {
        Name: "shoppollama-igw",
        Environment: environment,
    },
});

// Create Public Subnets
const publicSubnet1 = new aws.ec2.Subnet("shoppollama-public-subnet-1", {
    vpcId: vpc.id,
    cidrBlock: "10.0.1.0/24",
    availabilityZone: aws.getAvailabilityZones().then((zones: aws.GetAvailabilityZonesResult) => zones.names[0]),
    mapPublicIpOnLaunch: true,
    tags: {
        Name: "shoppollama-public-subnet-1",
        Environment: environment,
    },
});

const publicSubnet2 = new aws.ec2.Subnet("shoppollama-public-subnet-2", {
    vpcId: vpc.id,
    cidrBlock: "10.0.2.0/24",
    availabilityZone: aws.getAvailabilityZones().then((zones: aws.GetAvailabilityZonesResult) => zones.names[1]),
    mapPublicIpOnLaunch: true,
    tags: {
        Name: "shoppollama-public-subnet-2",
        Environment: environment,
    },
});

// Create Route Table
const routeTable = new aws.ec2.RouteTable("shoppollama-rt", {
    vpcId: vpc.id,
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
new aws.ec2.RouteTableAssociation("shoppollama-rta-1", {
    subnetId: publicSubnet1.id,
    routeTableId: routeTable.id,
});

new aws.ec2.RouteTableAssociation("shoppollama-rta-2", {
    subnetId: publicSubnet2.id,
    routeTableId: routeTable.id,
});

// Create Security Group for ALB (declared first to avoid forward reference)
const albSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-alb-sg", {
    vpcId: vpc.id,
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

// Create Security Group for EC2
const ec2SecurityGroup = new aws.ec2.SecurityGroup("shoppollama-ec2-sg", {
    vpcId: vpc.id,
    ingress: [
        {
            protocol: "tcp",
            fromPort: 4000,
            toPort: 4000,
            securityGroups: [albSecurityGroup.id], // Allow traffic from ALB
        },
        {
            protocol: "tcp",
            fromPort: 22,
            toPort: 22,
            cidrBlocks: ["0.0.0.0/0"], // SSH access (restrict in production)
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

// Create IAM Role for EC2
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

// Create Instance Profile
const instanceProfile = new aws.iam.InstanceProfile("shoppollama-instance-profile", {
    role: ec2Role.name,
});

// User data script for EC2 instance
const userData = `#!/bin/bash
yum update -y
yum install -y docker
service docker start
usermod -a -G docker ec2-user

# Install docker-compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /home/ec2-user/shoppollama
cd /home/ec2-user/shoppollama

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  shoppollama:
    image: nginx:alpine
    ports:
      - "4000:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    restart: unless-stopped
EOF

# Create startup script
cat > start.sh << 'EOF'
#!/bin/bash
cd /home/ec2-user/shoppollama

# Create HTML directory and basic page
mkdir -p html
cat > html/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Shoppollama - Deployed on AWS</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .container { max-width: 800px; margin: 0 auto; }
        .success { color: #28a745; font-size: 2em; }
        .info { color: #6c757d; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">🚀 Shoppollama is Running!</h1>
        <p class="info">Successfully deployed on AWS with Pulumi</p>
        <p class="info">Load Balancer: <strong>shoppollama-alb-f4806b8-1439723756.us-east-1.elb.amazonaws.com</strong></p>
        <p class="info">Instance Type: EC2 behind Application Load Balancer</p>
        <p class="info">Deployment Time: <script>document.write(new Date().toLocaleString());</script></p>
    </div>
</body>
</html>
HTML_EOF

docker-compose down
docker-compose up -d
EOF

chmod +x start.sh

# Run the application
./start.sh
`;

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
    subnets: [publicSubnet1.id, publicSubnet2.id],
    tags: {
        Name: "shoppollama-alb",
        Environment: environment,
    },
});

// Create Target Group
const targetGroup = new aws.lb.TargetGroup("shoppollama-tg", {
    port: 4000,
    protocol: "HTTP",
    vpcId: vpc.id,
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
    vpcZoneIdentifiers: [publicSubnet1.id, publicSubnet2.id],
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
export const vpcId = vpc.id;
export const instanceProfileArn = instanceProfile.arn;
