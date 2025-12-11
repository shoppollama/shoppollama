# Shoppollama AWS Deployment

This guide explains how to deploy Shoppollama to AWS using Pulumi with an EC2 instance behind an Application Load Balancer.

## Prerequisites

1. **AWS Account**: Ensure you have an AWS account with appropriate permissions
2. **AWS CLI**: Install and configure AWS CLI
   ```bash
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   aws configure
   ```
3. **Pulumi CLI**: Install Pulumi
   ```bash
   curl -fsSL https://get.pulumi.com | sh
   ```
4. **Node.js**: Install Node.js (version 18 or higher)
5. **Docker**: Install Docker locally for testing

## Infrastructure Overview

The deployment creates the following AWS resources:

- **VPC**: Custom VPC with public subnets
- **Application Load Balancer**: Public ALB for distributing traffic
- **EC2 Instance**: Auto Scaling Group with 1-3 instances
- **Security Groups**: Properly configured SGs for ALB and EC2
- **IAM Role**: EC2 instance role with SSM access
- **Target Group**: Health checks and target registration

## Deployment Steps

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Pulumi

```bash
# Login to Pulumi (if not already logged in)
pulumi login

# Create and select a stack (dev or prod)
./deploy.sh dev
# or
./deploy.sh prod
```

### 3. Deploy

```bash
# Deploy to dev environment
./deploy.sh dev

# Deploy to production
./deploy.sh prod
```

The deployment script will:
1. Install dependencies
2. Build the TypeScript code
3. Show a preview of changes
4. Ask for confirmation
5. Deploy the infrastructure

### 4. Access Your Application

After deployment, you'll get the Load Balancer URL:
```
🌐 Load Balancer URL: http://shoppollama-alb-1234567890.us-east-1.elb.amazonaws.com
```

## Configuration

### Environment Variables

You can configure the deployment using stack configuration files:

- `Pulumi.dev.yaml`: Development settings
- `Pulumi.prod.yaml`: Production settings

Key configuration options:
- `aws:region`: AWS region (default: us-east-1)
- `shoppollama:instanceType`: EC2 instance type (default: t3.medium)
- `shoppollama:environment`: Environment name (default: prod)

### Custom Configuration

To customize settings, edit the stack configuration files:

```yaml
config:
  aws:region: us-west-2
  shoppollama:instanceType: t3.large
  shoppollama:environment: staging
```

## Monitoring and Management

### Access EC2 Instances

Use AWS Systems Manager Session Manager:
```bash
aws ssm start-session --target <instance-id>
```

### View Logs

```bash
# SSH into the instance (if SSH is enabled)
ssh -i your-key.pem ec2-user@<instance-ip>

# View Docker logs
sudo docker-compose logs -f shoppollama
```

### Scale the Application

Modify the Auto Scaling Group settings in `index.ts`:
```typescript
const asg = new aws.autoscaling.Group("shoppollama-asg", {
    // ...
    minSize: 2,        // Minimum instances
    maxSize: 5,        // Maximum instances
    desiredCapacity: 2, // Desired instances
    // ...
});
```

## Security Considerations

1. **SSH Access**: The current configuration allows SSH from anywhere. Restrict this in production.
2. **HTTPS**: Consider adding SSL/TLS termination using AWS Certificate Manager.
3. **Database**: For production, use Amazon RDS instead of SQLite.
4. **Secrets**: Use AWS Secrets Manager for sensitive configuration.

## Cleanup

To destroy all resources and avoid charges:

```bash
./destroy.sh dev
# or
./destroy.sh prod
```

## Cost Optimization

- Use smaller instance types for development (t3.small)
- Enable Auto Scaling to match demand
- Consider using Spot Instances for cost savings
- Monitor costs using AWS Cost Explorer

## Troubleshooting

### Common Issues

1. **Build Failures**: Check Dockerfile and ensure all dependencies are available
2. **Health Check Failures**: Verify the application is running on port 4000
3. **Permission Errors**: Ensure IAM role has necessary permissions
4. **Network Issues**: Check security groups and NACLs

### Debug Commands

```bash
# Check instance status
aws ec2 describe-instances --filters Name=tag:Name,Values=shoppollama

# Check ALB logs
aws logs tail /aws/elasticloadbalancing/shoppollama-alb --follow

# Check Auto Scaling activities
aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>
```

## Production Enhancements

For production use, consider:

1. **HTTPS**: Add SSL certificate and HTTPS listener
2. **Database**: Migrate to Amazon RDS (PostgreSQL)
3. **CDN**: Add Amazon CloudFront for static assets
4. **Monitoring**: Enable CloudWatch alarms and detailed monitoring
5. **Backup**: Implement automated backup strategies
6. **Multi-AZ**: Deploy across multiple Availability Zones

## Support

For issues with:
- **Pulumi**: Check [Pulumi Documentation](https://www.pulumi.com/docs/)
- **AWS**: Check [AWS Documentation](https://docs.aws.amazon.com/)
- **Application**: Check application logs and configuration
