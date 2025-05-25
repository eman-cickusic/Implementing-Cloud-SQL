#!/bin/bash

# Cloud SQL Proxy Setup Script
# Run this script on the wordpress-proxy VM

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the SQL connection name from user input
get_connection_name() {
    echo -e "${BLUE}Cloud SQL Proxy Setup${NC}"
    echo "=================================="
    echo ""
    echo "You need to provide your Cloud SQL connection name."
    echo "Format: PROJECT_ID:REGION:INSTANCE_NAME"
    echo "Example: my-project:us-central1:wordpress-db"
    echo ""
    
    read -p "Enter your Cloud SQL connection name: " SQL_CONNECTION
    
    if [ -z "$SQL_CONNECTION" ]; then
        print_error "Connection name cannot be empty"
        exit 1
    fi
    
    # Validate format (basic check)
    if [[ ! $SQL_CONNECTION =~ ^[^:]+:[^:]+:[^:]+$ ]]; then
        print_warning "Connection name format may be incorrect"
        print_warning "Expected format: PROJECT_ID:REGION:INSTANCE_NAME"
        read -p "Continue anyway? (y/N): " CONFIRM
        if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    export SQL_CONNECTION
    echo "Using connection name: $SQL_CONNECTION"
}

# Download and setup Cloud SQL Proxy
setup_proxy() {
    print_step "Downloading Cloud SQL Proxy..."
    
    if [ -f "cloud_sql_proxy" ]; then
        print_warning "Cloud SQL Proxy already exists. Removing old version..."
        rm -f cloud_sql_proxy
    fi
    
    wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
    chmod +x cloud_sql_proxy
    
    echo "Cloud SQL Proxy downloaded and made executable!"
}

# Test proxy connection
test_proxy() {
    print_step "Testing proxy connection..."
    
    # Kill any existing proxy processes
    pkill -f cloud_sql_proxy || true
    
    # Start proxy in background
    ./cloud_sql_proxy -instances=$SQL_CONNECTION=tcp:3306 &
    PROXY_PID=$!
    
    # Wait a moment for proxy to start
    sleep 3
    
    # Check if proxy is running
    if ps -p $PROXY_PID > /dev/null; then
        echo "Proxy started successfully (PID: $PROXY_PID)"
        echo "Proxy is listening on 127.0.0.1:3306"
        
        # Test connection
        if command -v mysql &> /dev/null; then
            echo "Testing MySQL connection..."
            timeout 5 mysql -h 127.0.0.1 -u root -p -e "SELECT 1;" 2>/dev/null || true
        fi
        
        return 0
    else
        print_error "Failed to start proxy"
        return 1
    fi
}

# Create systemd service for proxy
create_service() {
    print_step "Creating systemd service for Cloud SQL Proxy..."
    
    sudo tee /etc/systemd/system/cloud-sql-proxy.service > /dev/null <<EOF
[Unit]
Description=Google Cloud SQL Proxy
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/home/$(whoami)/cloud_sql_proxy -instances=$SQL_CONNECTION=tcp:3306
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Copy proxy to a system location
    sudo cp cloud_sql_proxy /usr/local/bin/
    sudo chown www-data:www-data /usr/local/bin/cloud_sql_proxy
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable cloud-sql-proxy
    
    echo "Systemd service created and enabled!"
}

# Display setup completion info
display_completion_info() {
    echo ""
    echo -e "${GREEN}Cloud SQL Proxy setup completed!${NC}"
    echo "=================================="
    echo ""
    echo "Connection Details:"
    echo "- SQL Connection: $SQL_CONNECTION"
    echo "- Local Address: 127.0.0.1:3306"
    echo "- Service Status: $(sudo systemctl is-active cloud-sql-proxy 2>/dev/null || echo 'not running')"
    echo ""
    echo "Usage Commands:"
    echo "- Start service: sudo systemctl start cloud-sql-proxy"
    echo "- Stop service: sudo systemctl stop cloud-sql-proxy"
    echo "- Check status: sudo systemctl status cloud-sql-proxy"
    echo "- View logs: sudo journalctl -u cloud-sql-proxy -f"
    echo ""
    echo "WordPress Configuration:"
    echo "- Database Host: 127.0.0.1"
    echo "- Database Name: wordpress"
    echo "- Username: root"
    echo "- Password: [Your Cloud SQL root password]"
    echo ""
    
    # Get external IP for WordPress access
    EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
    echo "WordPress URL: http://$EXTERNAL_IP"
}

# Start the proxy service
start_service() {
    print_step "Starting Cloud SQL Proxy service..."
    
    # Stop any existing proxy processes
    pkill -f cloud_sql_proxy || true
    
    # Start the service
    sudo systemctl start cloud-sql-proxy
    
    # Wait and check status
    sleep 2
    if sudo systemctl is-active --quiet cloud-sql-proxy; then
        echo "Cloud SQL Proxy service started successfully!"
    else
        print_error "Failed to start Cloud SQL Proxy service"
        echo "Check logs with: sudo journalctl -u cloud-sql-proxy -n 20"
        return 1
    fi
}

# Main execution
main() {
    echo "Starting Cloud SQL Proxy setup..."
    
    get_connection_name
    setup_proxy
    
    if test_proxy; then
        # Kill the test proxy
        pkill -f cloud_sql_proxy || true
        
        create_service
        start_service
        display_completion_info
    else
        print_error "Proxy connection test failed. Please check your connection name and try again."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "test")
        get_connection_name
        setup_proxy
        test_proxy
        ;;
    "service")
        if [ -z "$2" ]; then
            echo "Usage: $0 service [start|stop|status|restart]"
            exit 1
        fi
        sudo systemctl $2 cloud-sql-proxy
        ;;
    *)
        main
        ;;
esac