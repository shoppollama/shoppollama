import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as cloudflare from "@pulumi/cloudflare";

// Existing EC2 instance details (deployed via deploy-t4g-large.sh)
const EXISTING_INSTANCE_ID = "i-05404bca03804ba88";
const EXISTING_INSTANCE_IP = "44.223.109.12";
const DOMAIN_NAME = "shoppollama.xyz";

// Create new VPC
const vpc = new aws.ec2.Vpc("shoppollama-vpc", {
    cidrBlock: "10.0.0.0/16",
    enableDnsHostnames: true,
    enableDnsSupport: true,
    tags: {
        Name: "shoppollama-vpc",
    },
});

// Create Internet Gateway
const igw = new aws.ec2.InternetGateway("shoppollama-igw", {
    vpcId: vpc.id,
    tags: {
        Name: "shoppollama-igw",
    },
});

// Create public subnets in different AZs for ALB
const publicSubnet1 = new aws.ec2.Subnet("shoppollama-public-1", {
    vpcId: vpc.id,
    cidrBlock: "10.0.1.0/24",
    availabilityZone: "us-east-1a",
    mapPublicIpOnLaunch: true,
    tags: {
        Name: "shoppollama-public-1",
    },
});

const publicSubnet2 = new aws.ec2.Subnet("shoppollama-public-2", {
    vpcId: vpc.id,
    cidrBlock: "10.0.2.0/24",
    availabilityZone: "us-east-1b",
    mapPublicIpOnLaunch: true,
    tags: {
        Name: "shoppollama-public-2",
    },
});

// Create route table
const routeTable = new aws.ec2.RouteTable("shoppollama-rt", {
    vpcId: vpc.id,
    routes: [{
        cidrBlock: "0.0.0.0/0",
        gatewayId: igw.id,
    }],
    tags: {
        Name: "shoppollama-rt",
    },
});

// Associate route table with subnets
const rtAssoc1 = new aws.ec2.RouteTableAssociation("shoppollama-rta-1", {
    subnetId: publicSubnet1.id,
    routeTableId: routeTable.id,
});

const rtAssoc2 = new aws.ec2.RouteTableAssociation("shoppollama-rta-2", {
    subnetId: publicSubnet2.id,
    routeTableId: routeTable.id,
});

// Security group for ALB
const albSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-alb-sg", {
    vpcId: vpc.id,
    ingress: [
        {
            protocol: "tcp",
            fromPort: 80,
            toPort: 80,
            cidrBlocks: ["0.0.0.0/0"],
        },
        {
            protocol: "tcp",
            fromPort: 443,
            toPort: 443,
            cidrBlocks: ["0.0.0.0/0"],
        },
    ],
    egress: [{
        protocol: "-1",
        fromPort: 0,
        toPort: 0,
        cidrBlocks: ["0.0.0.0/0"],
    }],
    tags: {
        Name: "shoppollama-alb-sg",
    },
});

// Create Application Load Balancer
const alb = new aws.lb.LoadBalancer("shoppollama-alb", {
    internal: false,
    loadBalancerType: "application",
    securityGroups: [albSecurityGroup.id],
    subnets: [publicSubnet1.id, publicSubnet2.id],
    enableDeletionProtection: false,
    tags: {
        Name: "shoppollama-alb",
    },
});

// Create target group pointing to existing EC2 instance IP
const targetGroup = new aws.lb.TargetGroup("shoppollama-tg", {
    port: 4000,
    protocol: "HTTP",
    targetType: "ip",
    vpcId: vpc.id,
    healthCheck: {
        enabled: true,
        path: "/",
        port: "4000",
        protocol: "HTTP",
        healthyThreshold: 2,
        unhealthyThreshold: 3,
        timeout: 5,
        interval: 30,
    },
    tags: {
        Name: "shoppollama-tg",
    },
});

// Register existing EC2 instance IP as target
const targetGroupAttachment = new aws.lb.TargetGroupAttachment("shoppollama-tg-attachment", {
    targetGroupArn: targetGroup.arn,
    targetId: EXISTING_INSTANCE_IP,
    port: 4000,
});

// HTTP listener - redirect to HTTPS or forward to target
const httpListener = new aws.lb.Listener("shoppollama-http-listener", {
    loadBalancerArn: alb.arn,
    port: 80,
    protocol: "HTTP",
    defaultActions: [{
        type: "forward",
        targetGroupArn: targetGroup.arn,
    }],
});

// Get Cloudflare zone
const cloudflareZone = cloudflare.getZone({
    name: DOMAIN_NAME,
} as any);

// Create/Update Cloudflare DNS record to point to ALB
const dnsRecord = new cloudflare.Record("shoppollama-dns", {
    zoneId: cloudflareZone.then(zone => zone.id),
    name: "@",
    type: "CNAME",
    content: alb.dnsName,
    proxied: true,
    ttl: 1, // Auto TTL when proxied
});

// Create www subdomain
const wwwRecord = new cloudflare.Record("shoppollama-www-dns", {
    zoneId: cloudflareZone.then(zone => zone.id),
    name: "www",
    type: "CNAME",
    content: alb.dnsName,
    proxied: true,
    ttl: 1,
});

// Export outputs
export const vpcId = vpc.id;
export const albDnsName = alb.dnsName;
export const albArn = alb.arn;
export const targetGroupArn = targetGroup.arn;
export const existingInstanceIp = EXISTING_INSTANCE_IP;
export const existingInstanceId = EXISTING_INSTANCE_ID;
export const applicationUrl = pulumi.interpolate`http://${DOMAIN_NAME}`;
export const albUrl = pulumi.interpolate`http://${alb.dnsName}`;
