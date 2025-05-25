#!/bin/bash

# Google Cloud SQL WordPress Implementation Setup Script
# This script automates the setup process for the Cloud SQL lab

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
DB_INSTANCE_NAME="wordpress-db"
DB_PASSWORD=""
NETWORK_NAME="default"

print_header() {
    echo -e "${BLUE}=================================="
    echo -e "  Cloud SQL WordPress Setup"
    echo -e "==================================${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    echo "Prerequisites check passed!"
}

get_user_input() {
    print_step "Gathering configuration information..."
    
    # Get project ID
    if [ -z "$PROJECT_ID" ]; then
        CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        read -p "Enter your Google Cloud Project ID [$CURRENT_PROJECT]: " PROJECT_ID
        PROJECT_ID=${PROJECT_ID:-$CURRENT_PROJECT}
    fi
    
    # Get region
    read -p "Enter your preferred region [$REGION]: " USER_REGION
    REGION=${USER_REGION:-$REGION}
    
    # Get database password
    while [ -z "$DB_PASSWORD" ]; do
        read -s -p "Enter a secure password for the Cloud SQL root user: " DB_PASSWORD
        echo
        if [ ${#DB_PASSWORD} -lt 8 ]; then
            print_warning "Password should be at least 8 characters long."
            DB_PASSWORD=""
        fi
    done
    
    echo -e "\nConfiguration:"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Database Instance: $DB_INSTANCE_NAME"
    echo "Network: $NETWORK_NAME"
    
    read -p "Continue with this configuration? (y/N): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
}

enable_apis() {
    print_step "Enabling required APIs..."
    
    gcloud services enable sqladmin.googleapis.com --project=$PROJECT_ID
    gcloud services enable compute.googleapis.com --project=$PROJECT_ID
    gcloud services enable servicenetworking.googleapis.com --project=$PROJECT_ID
    
    echo "APIs enabled successfully!"
}

create_cloud_sql_instance() {
    print_step "Creating Cloud SQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe $DB_INSTANCE_NAME --project=$PROJECT_ID &> /dev/null; then
        print_warning "Cloud SQL instance '$DB_INSTANCE_NAME' already exists. Skipping creation."
        return 0
    fi
    
    # Create the Cloud SQL instance
    gcloud sql instances create $DB_INSTANCE_NAME \
        --database-version=MYSQL_5_7 \
        --tier=db-custom-1-3840 \
        --region=$REGION \
        --network=$NETWORK_NAME \
        --no-assign-ip \
        --root-password="$DB_PASSWORD" \
        --storage-type=SSD \
        --storage-size=10GB \
        --storage-auto-increase \
        --project=$PROJECT_ID
    
    print_step "Waiting for Cloud SQL instance to be ready..."
    gcloud sql instances patch $DB_INSTANCE_NAME \
        --project=$PROJECT_ID \
        --quiet
        
    echo "Cloud SQL instance created successfully!"
}

create_wordpress_database() {
    print_step "Creating WordPress database..."
    
    # Check if database already exists
    if gcloud sql databases describe wordpress --instance=$DB_INSTANCE_NAME --project=$PROJECT_ID &> /dev/null; then
        print_warning "Database 'wordpress' already exists. Skipping creation."
        return 0
    fi
    
    gcloud sql databases create wordpress \
        --instance=$DB_INSTANCE_NAME \
        --project=$PROJECT_ID
    
    echo "WordPress database created successfully!"
}

create_compute_instances() {
    print_step "Creating Compute Engine instances..."
    
    # Startup script for WordPress installation
    cat > /tmp/wordpress-startup.sh << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y apache2 php php-mysql mysql-client

# Download and configure WordPress
cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Start Apache
systemctl enable apache2
systemctl start apache2

# Install Cloud SQL Proxy
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O /usr/local/bin/cloud_sql_proxy
chmod +x /usr/local/bin/cloud_sql_proxy
EOF

    # Create wordpress-proxy instance
    if ! gcloud compute instances describe wordpress-proxy --zone=$ZONE --project=$PROJECT_ID &> /dev/null; then
        gcloud compute instances create wordpress-proxy \
            --zone=$ZONE \
            --machine-type=e2-medium \
            --network-interface=network-tier=PREMIUM,subnet=default \
            --maintenance-policy=MIGRATE \
            --service-account=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
            --scopes=https://www.googleapis.com/auth/cloud-platform \
            --tags=http-server \
            --image-family=debian-11 \
            --image-project=debian-cloud \
            --boot-disk-size=10GB \
            --boot-disk-type=pd-standard \
            --metadata-from-file startup-script=/tmp/wordpress-startup.sh \
            --project=$PROJECT_ID
    else
        print_warning "Instance 'wordpress-proxy' already exists. Skipping creation."
    fi
    
    # Create wordpress-private-ip instance
    if ! gcloud compute instances describe wordpress-private-ip --zone=$ZONE --project=$PROJECT_ID &> /dev/null; then
        gcloud compute instances create wordpress-private-ip \
            --zone=$ZONE \
            --machine-type=e2-medium \
            --network-interface=network-tier=PREMIUM,subnet=default \
            --maintenance-policy=MIGRATE \
            --service-account=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
            --scopes=https://www.googleapis.com/auth/cloud-platform \
            --tags=http-server \
            --image-family=debian-11 \
            --image-project=debian-cloud \
            --boot-disk-size=10GB \
            --boot-disk-type=pd-standard \
            --metadata-from-file startup-script=/tmp/wordpress-startup.sh \
            --project=$PROJECT_ID
    else
        print_warning "Instance 'wordpress-private-ip' already exists. Skipping creation."
    fi
    
    rm /tmp/wordpress-startup.sh
    echo "Compute Engine instances created successfully!"
}

create_firewall_rules() {
    print_step "Creating firewall rules..."
    
    if ! gcloud compute firewall-rules describe allow-http --project=$PROJECT_ID &> /dev/null; then
        gcloud compute firewall-rules create allow-http \
            --allow tcp:80 \
            --source-ranges 0.0.0.0/0 \
            --target-tags http-server \
            --project=$PROJECT_ID
    else
        print_warning "Firewall rule 'allow-http' already exists. Skipping creation."
    fi
    
    echo "Firewall rules created successfully!"
}

display_connection_info() {
    print_step "Gathering connection information..."
    
    # Get Cloud SQL connection name
    CONNECTION_NAME=$(gcloud sql instances describe $DB_INSTANCE_NAME --project=$PROJECT_ID --format="value(connectionName)")
    
    # Get Cloud SQL private IP
    PRIVATE_IP=$(gcloud sql instances describe $DB_INSTANCE_NAME --project=$PROJECT_ID --format="value(ipAddresses[0].ipAddress)")
    
    # Get Compute Engine external IPs
    PROXY_IP=$(gcloud compute instances describe wordpress-proxy --zone=$ZONE --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
    PRIVATE_IP_INSTANCE_IP=$(gcloud compute instances describe wordpress-private-ip --zone=$ZONE --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
    
    echo -e "\n${GREEN}Setup completed successfully!${NC}"
    echo -e "\n${BLUE}Connection Information:${NC}"
    echo "=================================="
    echo "Cloud SQL Connection Name: $CONNECTION_NAME"
    echo "Cloud SQL Private IP: $PRIVATE_IP"
    echo "WordPress Proxy Instance: http://$PROXY_IP"
    echo "WordPress Private IP Instance: http://$PRIVATE_IP_INSTANCE_IP"
    echo "Database Name: wordpress"
    echo "Database Username: root"
    echo "Database Password: [The password you entered]"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Wait 2-3 minutes for instances to finish starting up"
    echo "2. SSH into wordpress-proxy and run the proxy setup script"
    echo "3. Configure WordPress on both instances using the IPs above"
    echo "4. For proxy connection, use Database Host: 127.0.0.1"
    echo "5. For private IP connection, use Database Host: $PRIVATE_IP"
}

cleanup_on_error() {
    print_error "Setup failed. You may need to clean up resources manually."
    print_error "Check the Google Cloud Console for any partially created resources."
}

main() {
    print_header
    
    # Set error trap
    trap cleanup_on_error ERR
    
    check_prerequisites
    get_user_input
    
    # Set project
    gcloud config set project $PROJECT_ID
    
    enable_apis
    create_cloud_sql_instance
    create_wordpress_database
    create_compute_instances
    create_firewall_rules
    display_connection_info
}

# Run main function
main "$@"