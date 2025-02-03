#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script needs to be run with root privileges"
    exit 1
fi

# Function to check domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain is correctly pointed
    else
        return 1  # Domain is not pointed
    fi
}

# Get user input
read -p "Enter your subdomain (e.g., tudong1.thaipham.top): " DOMAIN
read -p "Enter instance name (e.g., n8n1): " INSTANCE_NAME
read -p "Enter port number (e.g., 5678): " PORT

# Validate domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN is correctly pointed. Continuing installation."
else
    echo "Domain $DOMAIN is not pointed to this server."
    echo "Update your DNS record to point $DOMAIN to $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again."
    exit 1
fi

# Define instance directory
N8N_DIR="/home/$INSTANCE_NAME"

# Install Docker and Docker Compose if not installed
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Create instance directory
mkdir -p $N8N_DIR

# Create docker-compose.yml
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"

services:
  $INSTANCE_NAME:
    image: n8nio/n8n
    restart: always
    ports:
      - "$PORT:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=$PORT
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $N8N_DIR:/home/node/.n8n

volumes:
  caddy_data:
  caddy_config:
EOF

# Update global Caddyfile
CADDYFILE_PATH="/etc/caddy/Caddyfile"

if ! grep -q "$DOMAIN" "$CADDYFILE_PATH"; then
    echo "$DOMAIN {" >> $CADDYFILE_PATH
    echo "    reverse_proxy localhost:$PORT" >> $CADDYFILE_PATH
    echo "}" >> $CADDYFILE_PATH
fi

# Set permissions
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Start the instance
cd $N8N_DIR
docker-compose up -d

# Reload Caddy to apply changes
docker exec -w /etc/caddy caddy caddy reload

echo "n8n instance $INSTANCE_NAME has been installed at https://${DOMAIN}."
echo "Configuration files are stored in $N8N_DIR."
