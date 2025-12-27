# Shoppollama Pulumi + Mix Release Deployment

This guide explains how to deploy Shoppollama using a hybrid approach: **Pulumi for AWS infrastructure** and **mix releases for application deployment** with **Caddy as the reverse proxy**.

## Overview

This deployment approach combines the best of both worlds:
- **Pulumi**: Infrastructure as Code for AWS resources (VPC, EC2, ALB, Auto Scaling)
- **Mix Releases**: Self-contained Elixir deployments for better performance
- **Caddy**: Modern reverse proxy with automatic HTTPS
- **GitHub Actions**: Automated CI/CD pipeline
- **systemd**: Process management on EC2 instances

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Actions│────│  AWS Load       │────│   EC2 Instance  │
│   (CI/CD)       │    │  Balancer       │    │   (Elixir +     │
│                 │    │                 │    │    Caddy)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │                        │
                              ▼                        ▼
                       ┌─────────────┐         ┌─────────────┐
                       │   Internet  │         │  Phoenix    │
                       │   Traffic   │         │  App (4001) │
                       └─────────────┘         └─────────────┘
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Pulumi CLI** installed locally
3. **Node.js** (version 18 or higher)
4. **Elixir/OTP** for local development
5. **GitHub repository** with the project code

## Infrastructure Setup

### 1. Install Dependencies

```bash
# Install Pulumi
curl -fsSL https://get.pulumi.com | sh

# Install Node.js dependencies
npm install
```

### 2. Configure AWS CLI

```bash
aws configure
# Enter your AWS credentials and region (us-east-1)
```

### 3. Deploy Infrastructure

```bash
# Deploy to production
./deploy.sh prod

# Or deploy to development
./deploy.sh dev
```

This creates:
- **VPC** with public subnets
- **Application Load Balancer** for traffic distribution
- **EC2 instances** with Elixir, Caddy, and systemd pre-configured
- **Security Groups** for proper traffic flow
- **Auto Scaling Group** for high availability

## GitHub Actions Configuration

### Required Secrets

Configure these secrets in your GitHub repository:

1. **AWS Credentials:**
   - `AWS_ACCESS_KEY_ID`: Your AWS access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret key

2. **SSH Access:**
   - `SSH_KEY`: Private SSH key for EC2 access
   - `SSH_USER`: SSH username (typically `ec2-user`)

### Generate SSH Key

```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -C "github-actions-deploy"

# The deployment process will automatically configure SSH access
# Add the private key to GitHub secrets
cat ~/.ssh/id_rsa
```

## Deployment Process

### Automatic Deployment

When you push to the `main` branch:

1. **Build Phase:**
   - Compile Elixir code and assets
   - Build mix release
   - Cache dependencies for faster builds

2. **Infrastructure Phase:**
   - Get deployment details from Pulumi stack
   - Resolve load balancer and instance information

3. **Deploy Phase:**
   - Deploy mix release via rsync
   - Configure environment variables
   - Run database migrations
   - Update Caddy configuration
   - Restart application service

### Manual Deployment

You can also deploy manually:

```bash
# Build release locally
MIX_ENV=prod mix release

# Get instance details from Pulumi
pulumi stack select prod
pulumi stack output loadBalancerDns

# Deploy to server (replace with actual instance IP)
rsync -avz ./_build/prod ec2-user@INSTANCE_IP:/var/www/shoppollama/

# Run migrations and restart
ssh ec2-user@INSTANCE_IP "cd /var/www/shoppollama && ./deploy.sh"
```

## Server Configuration

### Pre-installed Components

Each EC2 instance comes with:

- **Elixir/OTP**: Latest stable version
- **Caddy**: Reverse proxy with automatic HTTPS
- **SQLite**: Database (can be upgraded to PostgreSQL)
- **systemd**: Service management
- **Python3**: For initial health check server

### Directory Structure

```
/var/www/shoppollama/
├── .env                    # Environment variables
├── .env.template          # Environment template
├── _build/prod/rel/       # Mix release files
├── priv/static/           # Static assets
└── deploy.sh              # Deployment script
```

### Service Management

```bash
# Check application status
sudo systemctl status shoppollama

# View application logs
sudo journalctl -u shoppollama -f

# Restart application
sudo systemctl restart shoppollama

# Check Caddy status
sudo systemctl status caddy

# View Caddy logs
sudo journalctl -u caddy -f
```

## Configuration

### Environment Variables

Edit `/var/www/shoppollama/.env` on the server:

```bash
PHX_HOST=your-load-balancer-dns.amazonaws.com
PORT=4001
PHX_SERVER=true
SECRET_KEY_BASE=your-secret-key
MIX_ENV=prod
DATABASE_URL=ecto://user:pass@localhost/shoppollama
```

### Caddy Configuration

The Caddyfile is automatically configured with your load balancer DNS:

```caddy
your-load-balancer-dns.amazonaws.com {
    root * /var/www/shoppollama
    encode zstd gzip
    reverse_proxy localhost:4001
    header -Server
    log {
        output file /var/log/caddy/access_shoppollama.log
    }
}
```

## Monitoring and Troubleshooting

### Health Checks

- **Load Balancer**: Checks port 4000 on instances
- **Application**: Runs on port 4001 internally
- **Caddy**: Handles external traffic on ports 80/443

### Logs

```bash
# Application logs
sudo journalctl -u shoppollama -f

# Caddy access logs
tail -f /var/log/caddy/access_shoppollama.log

# Caddy service logs
sudo journalctl -u caddy -f

# System logs
sudo journalctl -f
```

### Debug Commands

```bash
# Connect to running application
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama remote

# Run migrations manually
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/migrate

# Test database connection
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama eval "Shoppollama.Repo.query('SELECT 1')"
```

## Scaling and High Availability

### Auto Scaling

The infrastructure includes:

- **Auto Scaling Group**: 1-3 instances (configurable)
- **Load Balancer**: Distributes traffic across healthy instances
- **Health Checks**: Automatic instance replacement

### Scaling Configuration

Update `index.ts` to adjust scaling:

```typescript
const asg = new aws.autoscaling.Group("shoppollama-asg", {
    // ... other config
    minSize: 2,        // Minimum instances
    maxSize: 5,        // Maximum instances
    desiredCapacity: 2, // Desired instances
    // ...
});
```

## Security Considerations

### Network Security

- **VPC**: Isolated network environment
- **Security Groups**: Restrict traffic to necessary ports
- **Load Balancer**: Public-facing, instances are private

### Application Security

- **Environment Variables**: Sensitive data in .env file
- **HTTPS**: Automatic SSL certificates via Caddy
- **SSH Keys**: Secure access for deployment

### Production Recommendations

1. **Restrict SSH access** to specific IP ranges
2. **Use PostgreSQL** instead of SQLite for production
3. **Enable CloudWatch alarms** for monitoring
4. **Implement backup strategies** for database
5. **Use AWS Secrets Manager** for sensitive configuration

## Cost Optimization

- **Instance Types**: Choose appropriate size (t3.small for dev, t3.medium for prod)
- **Auto Scaling**: Match capacity to demand
- **Spot Instances**: Up to 90% cost savings for stateless workloads
- **Reserved Instances**: Up to 40% savings for predictable workloads

## Migration from Docker

If migrating from the existing Docker setup:

1. **Backup data** from existing deployment
2. **Deploy new infrastructure** with Pulumi
3. **Update GitHub Actions** with new secrets
4. **Deploy application** using mix releases
5. **Update DNS** to point to new load balancer
6. **Decommission old resources** after verification

## Maintenance

### Regular Tasks

- **Monitor logs** for errors and performance issues
- **Update dependencies** (Elixir, Erlang, system packages)
- **Review security groups** and access patterns
- **Backup database** regularly
- **Test disaster recovery** procedures

### Updates

```bash
# Update system packages
sudo yum update -y

# Update Elixir/Erlang (requires careful planning)
# Follow official Elixir/Erlang upgrade guides

# Update Caddy
sudo yum update caddy

# Restart services after updates
sudo systemctl restart shoppollama caddy
```

## Support

For issues:
- **Infrastructure**: Check Pulumi state and AWS console
- **Deployment**: Review GitHub Actions logs
- **Application**: Check systemd logs and application logs
- **Network**: Verify security groups and load balancer configuration
