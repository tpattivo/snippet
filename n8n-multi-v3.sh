#!/bin/bash

# Check if the script is run with root privileges
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
        return 1  # Domain is not correctly pointed
    fi
}

# Get instance name from user
read -p "Enter the n8n instance name (e.g., n8n1, n8n2): " INSTANCE_NAME

# Construct the subdomain
DOMAIN="${INSTANCE_NAME}.thaipham.top"

# Check domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Create directory for the n8n instance
N8N_DIR="/home/$INSTANCE_NAME"
mkdir -p $N8N_DIR

# Create docker-compose.yml file
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "\${N8N_PORT}:5678" # Dynamic port mapping
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
      - "80:80"
      - "443:443"
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

# Create Caddyfile (Dynamically generated)
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
}
EOF

# Generate a random port
N8N_PORT=$(( ( RANDOM % 59857 ) + 5679 ))

# Set the dynamic port in docker-compose.yml
sed -i "s/\${N8N_PORT}/$N8N_PORT/" $N8N_DIR/docker-compose.yml

# Set permissions for the n8n directory
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Install Docker and Docker Compose (if not already installed) - Uncomment these if needed.
# apt-get update
# apt-get install -y apt-transport-https ca-certificates curl software-properties-common
# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
# add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
# apt-get update
# apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Start the containers
cd $N8N_DIR
docker-compose up -d

echo "n8n instance $INSTANCE_NAME has been installed and configured with SSL using Caddy. Access it at https://${DOMAIN}"
echo "Configuration files and data are stored in $N8N_DIR"
echo "n8n is listening on port $N8N_PORT inside the container."
