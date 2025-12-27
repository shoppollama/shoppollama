"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildServerPublicDns = exports.buildServerPublicIp = exports.instanceProfileArn = exports.vpcId = exports.loadBalancerUrl = exports.loadBalancerDns = void 0;
const pulumi = __importStar(require("@pulumi/pulumi"));
const aws = __importStar(require("@pulumi/aws"));
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
    availabilityZone: aws.getAvailabilityZones().then((zones) => zones.names[0]),
    mapPublicIpOnLaunch: true,
    tags: {
        Name: "shoppollama-public-subnet-1",
        Environment: environment,
    },
});
const publicSubnet2 = new aws.ec2.Subnet("shoppollama-public-subnet-2", {
    vpcId: vpc.id,
    cidrBlock: "10.0.2.0/24",
    availabilityZone: aws.getAvailabilityZones().then((zones) => zones.names[1]),
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
// Create Instance Profile
const instanceProfile = new aws.iam.InstanceProfile("shoppollama-instance-profile", {
    role: ec2Role.name,
});
// Create Security Group for Build Server
const buildSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-build-sg", {
    vpcId: vpc.id,
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
cat > deploy.sh << 'EOF'
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

echo "✅ Build complete!"
EOF

chmod +x deploy.sh

echo "✅ Build server ready!"
`;
// Create Build Server Instance
const buildInstance = new aws.ec2.Instance("shoppollama-build", {
    instanceType: "t3.medium",
    subnetId: publicSubnet1.id,
    ami: aws.getAmi({
        filters: [
            { name: "name", values: ["amzn2-ami-hvm-*-x86_64-gp2"] },
            { name: "virtualization-type", values: ["hvm"] },
        ],
        mostRecent: true,
    }).then((ami) => ami.id),
    vpcSecurityGroupIds: [buildSecurityGroup.id],
    iamInstanceProfile: instanceProfile,
    userData: Buffer.from(buildServerUserData).toString("base64"),
    tags: {
        Name: "shoppollama-build",
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
// User data script for EC2 instance - Mix Release with Caddy
const userData = `#!/bin/bash
yum update -y

# Install Caddy
yum install -y yum-utils
yum-config-manager --add-repo=https://dl.cloudsmith.io/public/caddy/stable/rpm/
rpm --import https://dl.cloudsmith.io/public/caddy/stable/gpg.key
yum install -y caddy

# Install SQLite for database
yum install -y sqlite sqlite-devel

# Create app directory
mkdir -p /var/www/shoppollama
cd /var/www/shoppollama

# Create environment file template
cat > .env.template << 'EOF'
PHX_HOST=your-domain.com
PORT=4001
PHX_SERVER=true
SECRET_KEY_BASE=your-secret-key-here
MIX_ENV=prod
DATABASE_URL=ecto://user:pass@localhost/shoppollama
EOF

# Create systemd service file
cat > /etc/systemd/system/shoppollama.service << 'EOF'
[Unit]
Description=Shoppollama Phoenix App

[Service]
User=root
EnvironmentFile=/var/www/shoppollama/.env
Environment=LANG=en_US.utf8
WorkingDirectory=/var/www/shoppollama/
ExecStart=/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama start
ExecStop=/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama stop
KillMode=process
Restart=on-failure
LimitNOFILE=65535
SyslogIdentifier=shoppollama

[Install]
WantedBy=multi-user.target
EOF

# Configure Caddy
cat > /etc/caddy/Caddyfile << 'EOF'
shoppollama.yourdomain.com {
    root * /var/www/shoppollama
    encode zstd gzip
    reverse_proxy localhost:4001
    header -Server
    log {
        output file /var/log/caddy/access_shoppollama.log
    }
}
EOF

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable shoppollama
systemctl enable caddy
systemctl start caddy

# Create deployment script for receiving releases
cat > /home/ec2-user/receive-deploy.sh << 'EOF'
#!/bin/bash
cd /var/www/shoppollama

# Create .env file from template if it doesn't exist
if [ ! -f .env ]; then
    cp .env.template .env
    echo "⚠️ Please update the .env file with your database credentials"
fi

# Run migrations
export \$(cat .env | xargs) && ./_build/prod/rel/shoppollama/bin/migrate

# Restart application
systemctl daemon-reload
systemctl restart shoppollama

echo "✅ Deployment complete!"
EOF

chmod +x /home/ec2-user/receive-deploy.sh

echo "✅ Target server ready!"
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
    }).then((ami) => ami.id),
    instanceType: instanceType,
    userData: Buffer.from(userData).toString("base64"),
    vpcSecurityGroupIds: [ec2SecurityGroup.id],
    iamInstanceProfile: instanceProfile,
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
exports.loadBalancerDns = alb.dnsName;
exports.loadBalancerUrl = pulumi.interpolate `http://${alb.dnsName}`;
exports.vpcId = vpc.id;
exports.instanceProfileArn = instanceProfile.arn;
exports.buildServerPublicIp = buildInstance.publicIp;
exports.buildServerPublicDns = buildInstance.publicDns;
