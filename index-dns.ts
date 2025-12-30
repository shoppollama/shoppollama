import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";

// Hardcoded existing EC2 instance details
const EXISTING_INSTANCE_ID = "i-05404bca03804ba88";
const EXISTING_INSTANCE_IP = "44.223.109.12";
const DOMAIN_NAME = "shoppollama.xyz";

// Get the existing hosted zone for shoppollama.xyz
const hostedZone = aws.route53.getZone({
    name: DOMAIN_NAME,
    privateZone: false,
});

// Create A record pointing to the EC2 instance
const aRecord = new aws.route53.Record("shoppollama-a-record", {
    zoneId: hostedZone.then(zone => zone.zoneId),
    name: DOMAIN_NAME,
    type: "A",
    ttl: 300,
    records: [EXISTING_INSTANCE_IP],
});

// Create www subdomain pointing to the same IP
const wwwRecord = new aws.route53.Record("shoppollama-www-record", {
    zoneId: hostedZone.then(zone => zone.zoneId),
    name: `www.${DOMAIN_NAME}`,
    type: "A",
    ttl: 300,
    records: [EXISTING_INSTANCE_IP],
});

// Export outputs
export const instanceIp = EXISTING_INSTANCE_IP;
export const instanceId = EXISTING_INSTANCE_ID;
export const domainName = DOMAIN_NAME;
export const applicationUrl = `http://${DOMAIN_NAME}:4000`;
export const hostedZoneId = hostedZone.then(zone => zone.zoneId);
