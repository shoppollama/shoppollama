#!/bin/bash

# Shoppollama Server Setup Script
# This script sets up a Linux server for mix release deployment

set -e

echo "🚀 Setting up Shoppollama server..."

# Update system
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install basic dependencies
echo "🔧 Installing basic dependencies..."
sudo apt install -y build-essential git wget unzip curl software-properties-common

# Install Elixir/Erlang
echo "💧 Installing Elixir and Erlang..."
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt update
sudo apt install -y elixir erlang-dev erlang-parsetools erlang-tools

# Install Caddy
echo "🌐 Installing Caddy..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# Install SQLite
echo "🗄️ Installing SQLite..."
sudo apt install -y sqlite3 libsqlite3-dev

# Create deployment directory
echo "📁 Creating deployment directory..."
sudo mkdir -p /var/www/shoppollama
sudo chown -R $USER:$USER /var/www/shoppollama

# Generate secret key
echo "🔑 Generating secret key..."
SECRET_KEY=$(mix phx.gen.secret 2>/dev/null || echo "generate-secret-key-locally-and-replace-this")
echo "Generated secret key: $SECRET_KEY"

# Create environment file template
echo "📝 Creating environment file..."
cat > /var/www/shoppollama/.env << EOF
PHX_HOST=your-domain.com
PORT=4001
PHX_SERVER=true
SECRET_KEY_BASE=$SECRET_KEY
MIX_ENV=prod
DATABASE_URL=ecto://user:pass@localhost/shoppollama
EOF

echo "✅ Server setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Edit /var/www/shoppollama/.env with your actual domain and database credentials"
echo "2. Copy deployment/shoppollama.service to /etc/systemd/system/"
echo "3. Copy deployment/Caddyfile to /etc/caddy/Caddyfile"
echo "4. Configure GitHub Actions secrets for deployment"
echo "5. Push to main branch to trigger first deployment"
echo ""
echo "🔧 Service management commands:"
echo "  sudo systemctl enable shoppollama"
echo "  sudo systemctl start shoppollama"
echo "  sudo systemctl status shoppollama"
