import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as cloudflare from "@pulumi/cloudflare";

// Existing EC2 instance details (deployed via deploy-t4g-large.sh)
const EXISTING_INSTANCE_ID = "i-05404bca03804ba88";
const EXISTING_INSTANCE_PUBLIC_IP = "44.223.109.12";
const EXISTING_INSTANCE_PRIVATE_IP = "10.0.1.105"; // Private IP for ALB target group
const DOMAIN_NAME = "shoppollama.xyz";

// Use existing VPC and subnets
const EXISTING_VPC_ID = "vpc-083d38d951d2954e8";
const EXISTING_SUBNET_1 = "subnet-099485b1570792810"; // us-east-1a
const EXISTING_SUBNET_2 = "subnet-0f4bd71ebf91a16c5"; // us-east-1b

// Reference existing VPC
const vpc = aws.ec2.getVpc({
    id: EXISTING_VPC_ID,
});

// Reference existing subnets
const publicSubnet1 = aws.ec2.getSubnet({
    id: EXISTING_SUBNET_1,
});

const publicSubnet2 = aws.ec2.getSubnet({
    id: EXISTING_SUBNET_2,
});

// Security group for ALB
const albSecurityGroup = new aws.ec2.SecurityGroup("shoppollama-alb-sg", {
    vpcId: vpc.then(v => v.id),
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
    subnets: [publicSubnet1.then(s => s.id), publicSubnet2.then(s => s.id)],
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
    vpcId: vpc.then(v => v.id),
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
    targetId: EXISTING_INSTANCE_PRIVATE_IP,
    port: 4000,
});

// Request ACM certificate for the domain
const certificate = new aws.acm.Certificate("shoppollama-cert", {
    domainName: DOMAIN_NAME,
    subjectAlternativeNames: [`www.${DOMAIN_NAME}`],
    validationMethod: "DNS",
    tags: {
        Name: "shoppollama-cert",
    },
});

// HTTP listener - redirect to HTTPS
const httpListener = new aws.lb.Listener("shoppollama-http-listener", {
    loadBalancerArn: alb.arn,
    port: 80,
    protocol: "HTTP",
    defaultActions: [{
        type: "redirect",
        redirect: {
            port: "443",
            protocol: "HTTPS",
            statusCode: "HTTP_301",
        },
    }],
});

// Wait for certificate validation (manual DNS validation required)
const certificateValidation = new aws.acm.CertificateValidation("shoppollama-cert-validation", {
    certificateArn: certificate.arn,
});

// HTTPS listener with SSL certificate (depends on validation)
const httpsListener = new aws.lb.Listener("shoppollama-https-listener", {
    loadBalancerArn: alb.arn,
    port: 443,
    protocol: "HTTPS",
    sslPolicy: "ELBSecurityPolicy-TLS13-1-2-2021-06",
    certificateArn: certificateValidation.certificateArn,
    defaultActions: [{
        type: "forward",
        targetGroupArn: targetGroup.arn,
    }],
});

// Export outputs
export const vpcId = vpc.then(v => v.id);
export const albDnsName = alb.dnsName;
export const albArn = alb.arn;
export const targetGroupArn = targetGroup.arn;
export const existingInstanceIp = EXISTING_INSTANCE_PUBLIC_IP;
export const existingInstanceId = EXISTING_INSTANCE_ID;
export const applicationUrl = pulumi.interpolate`http://${DOMAIN_NAME}`;
export const albUrl = pulumi.interpolate`http://${alb.dnsName}`;
