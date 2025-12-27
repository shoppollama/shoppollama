# Shoppollama Mix Release Deployment

This guide explains how to deploy Shoppollama using Elixir mix releases with GitHub Actions and Caddy as the reverse proxy.

## Overview

This deployment approach uses:
- **Mix releases** for self-contained Elixir deployments
- **GitHub Actions** for automated CI/CD
- **Caddy** as a reverse proxy (instead of nginx)
- **systemd** for process management
- **SQLite** database (can be upgraded to PostgreSQL for production)

## Prerequisites

1. **Linux server** (Ubuntu 20.04+ recommended)
2. **Elixir/OTP** installed locally for development
3. **GitHub repository** with the project code
4. **SSH access** to the target server
5. **Domain name** pointing to your server (optional but recommended)

## Server Setup

### 1. Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Elixir/Erlang
sudo apt install -y build-essential git wget unzip curl

# Add Erlang Solutions repository
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update
sudo apt install -y elixir erlang-dev erlang-parsetools

# Install Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# Install SQLite (for database)
sudo apt install -y sqlite3 libsqlite3-dev
```

### 2. Create Deployment Directory

```bash
sudo mkdir -p /var/www/shoppollama
sudo chown -R $USER:$USER /var/www/shoppollama
```

### 3. Configure Environment

Create the environment file on the server:

```bash
# Generate a secret key
mix phx.gen.secret
```

Create `/var/www/shoppollama/.env`:

```bash
PHX_HOST=your-domain.com
PORT=4001
PHX_SERVER=true
SECRET_KEY_BASE=your-generated-secret-key
MIX_ENV=prod
DATABASE_URL=ecto://user:pass@localhost/shoppollama
```

### 4. Setup systemd Service

Copy the service file:

```bash
sudo cp deployment/shoppollama.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable shoppollama
```

### 5. Configure Caddy

Copy the Caddyfile:

```bash
sudo cp deployment/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## GitHub Actions Setup

### 1. Configure Secrets

In your GitHub repository, go to Settings > Secrets and add:

- `SSH_KEY`: Your private SSH key for server access
- `SSH_HOST`: Your server hostname or IP
- `SSH_USER`: Username for SSH connection

### 2. Generate SSH Key

```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -C "github-actions-deploy"

# Copy public key to server
ssh-copy-id -i ~/.ssh/id_rsa.pub user@your-server

# Add private key to GitHub secrets
cat ~/.ssh/id_rsa
```

## Deployment Process

### Automatic Deployment

Once configured, pushing to the `main` branch will automatically:

1. Build the mix release
2. Deploy to the server via rsync
3. Run database migrations
4. Restart the application

### Manual Deployment

You can also deploy manually:

```bash
# Build release locally
MIX_ENV=prod mix release

# Deploy to server
rsync -avz ./_build/prod user@server:/var/www/shoppollama/

# Run migrations on server
ssh user@server "cd /var/www/shoppollama && export \$(cat .env | xargs) && _build/prod/rel/shoppollama/bin/migrate"

# Restart service
ssh user@server "sudo systemctl restart shoppollama"
```

## Management Commands

### Service Management

```bash
# Start service
sudo systemctl start shoppollama

# Stop service
sudo systemctl stop shoppollama

# Restart service
sudo systemctl restart shoppollama

# Check status
sudo systemctl status shoppollama

# View logs
sudo journalctl -u shoppollama -f
```

### Application Management

```bash
# Connect to running application
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama remote

# Run migrations
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/migrate

# Rollback migrations
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama eval "Shoppollama.Release.rollback(Shoppollama.Repo, 0)"
```

## Monitoring and Logs

### Application Logs

```bash
# systemd logs
sudo journalctl -u shoppollama -f

# Application logs (if configured)
tail -f /var/www/shoppollama/log/production.log
```

### Caddy Logs

```bash
# Access logs
tail -f /var/log/caddy/access_shoppollama.log

# Caddy service logs
sudo journalctl -u caddy -f
```

## Security Considerations

1. **Firewall**: Configure UFW or similar firewall
2. **SSL/TLS**: Caddy automatically handles HTTPS with Let's Encrypt
3. **Database**: Consider PostgreSQL for production
4. **Secrets**: Use environment variables, never commit secrets
5. **Updates**: Regularly update Elixir, Erlang, and system packages

## Troubleshooting

### Common Issues

1. **Build failures**: Check Mix dependencies and Elixir version
2. **Migration errors**: Verify database connection and permissions
3. **Service won't start**: Check systemd logs and environment variables
4. **Caddy issues**: Verify DNS and certificate configuration

### Debug Commands

```bash
# Check application health
curl http://localhost:4001/health

# Test database connection
/var/www/shoppollama/_build/prod/rel/shoppollama/bin/shoppollama eval "Shoppollama.Repo.query('SELECT 1')"

# Verify release
ls -la /var/www/shoppollama/_build/prod/rel/shoppollama/
```

## Production Enhancements

For production use, consider:

1. **Database**: Upgrade to PostgreSQL or MySQL
2. **Monitoring**: Add health checks and metrics
3. **Backups**: Implement database backup strategy
4. **Scaling**: Consider load balancer and multiple instances
5. **CDN**: Add CloudFront for static assets
6. **Observability**: Add structured logging and tracing

## Migration from Docker/Pulumi

To migrate from the current Docker/Pulumi setup:

1. **Backup data**: Export database and any important files
2. **Install dependencies**: Follow server setup above
3. **Deploy new version**: Use GitHub Actions or manual deployment
4. **Update DNS**: Point domain to new server
5. **Decommission**: Remove old AWS resources after verification

## Support

For issues:
- **Application**: Check logs and configuration
- **Deployment**: Review GitHub Actions logs
- **Infrastructure**: Verify server setup and dependencies
