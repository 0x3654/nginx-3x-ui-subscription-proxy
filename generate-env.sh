#!/bin/bash
# Generate .env file from Ansible configs
# Usage: ./generate-env.sh

PORT="2097"
PATH="Kj8P2xZn5L"

# Get servers from configs - manual extraction
ae="ae.0x3654.com"
ae2="ae2.0x3654.com"
es="es.0x3654.com"
tr="tr.0x3654.com"
ru2="ru2.0x3654.com"

# Build servers list
SERVERS_LIST="https://$ae:$PORT/$PATH/ https://$ae2:$PORT/$PATH/ https://$es:$PORT/$PATH/ https://$tr:$PORT/$PATH/ https://$ru2:$PORT/$PATH/"

# Defaults
SITE_HOST="sub.0x3654.com"
SITE_PORT="443"
TLS_MODE="off"
SUB="sub"

# Prompt for SITE_HOST
read -p "Enter SITE_HOST [$SITE_HOST]: " input_host
SITE_HOST="${input_host:-$SITE_HOST}"

# Write .env
cat > .env << EOF
# Auto-generated from Ansible configs
# Generated at: $(date)

SERVERS="$SERVERS_LIST"

SITE_HOST=$SITE_HOST
SITE_PORT=$SITE_PORT
SUB=$SUB
TLS_MODE=$TLS_MODE
EOF

echo ""
echo "✅ .env file generated successfully!"
echo ""
echo "Servers configured:"
echo "$SERVERS_LIST" | tr ' ' '\n' | nl
echo ""
echo "Configuration:"
echo "  SITE_HOST=$SITE_HOST"
echo "  SITE_PORT=$SITE_PORT"
echo "  SUB=$SUB"
echo "  TLS_MODE=$TLS_MODE"
