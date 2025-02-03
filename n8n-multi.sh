#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# Function to check domain pointing
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain is correctly pointed
    else
        return 1  # Domain is not correctly pointed
    fi
}

# Get domain input from user
read -p "Enter your domain or subdomain: " DOMAIN

# Check domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Get unique installation directory
read -p "Enter a unique directory name for this instance (e.g., n8n1, n8n2): " INSTANCE_NAME
N8N_DIR="/home/$INSTANCE_NAME"

# Get a unique port for the instance
read -p "Enter a unique port for n8n (e.g., 5678, 5679): " N8N_PORT

# Check if this is the first instance (Caddy should use default 80/443)
if [[ ! -d "/home/n8n1" ]]; then
    CADDY_HTTP_PORT=80
    CADDY_HTTPS_PORT=443
    echo "This is the first n8n instance. Using default ports for Caddy (80/443)."
else
    # Ask user for custom Caddy ports to avoid conflicts
    read -p "Enter a unique HTTP port for Caddy (e.g., 8081, 8082): " CADDY_HTTP_PORT
    read -p "Enter a unique HTTPS port for Caddy (e.g., 444, 445): " CADDY_HTTPS_PORT
fi

# Install Docker and Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Create directory for n8n instance
mkdir -p $N8N_DIR

# Create docker-compose.yml file
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $N8N_DIR:/home/node/.n8n

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "${CADDY_HTTP_PORT}:80"
      - "${CADDY_HTTPS_PORT}:443"
    volumes:
      - $N8N_DIR/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n

volumes:
  caddy_data:
  caddy_config:
EOF

# Create Caddyfile
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
}
EOF

# Set permissions
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Start the containers
cd $N8N_DIR
docker-compose up -d

echo "n8n has been installed and configured with SSL using Caddy. Access it at https://${DOMAIN}"
echo "Configuration files and data are stored in $N8N_DIR"
