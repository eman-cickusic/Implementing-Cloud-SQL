#!/bin/bash

# Cloud SQL Monitoring and Health Check Script
# This script monitors the health of your Cloud SQL setup and provides troubleshooting tools

set -e

# Configuration
PROJECT_ID=""
INSTANCE_NAME="wordpress-db"
REGION="us-central1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}=================================="
    echo -e "  Cloud SQL Monitoring Dashboard"
    echo -e "==================================${NC}"
}

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_status() {
    local status=$1
    local message=$2
    
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" == "WARNING" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

get_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        fi
    fi
}

check_cloud_sql_status() {
    print_section "Cloud SQL Instance Status"
    
    local status=$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    case $status in
        "RUNNABLE")
            print_status "OK" "Cloud SQL instance is running"
            ;;
        "STOPPED")
            print_status "ERROR" "Cloud SQL instance is stopped"
            ;;
        "CREATING")
            print_status "WARNING" "Cloud SQL instance is being created"
            ;;
        "NOT_FOUND")
            print_status "ERROR" "Cloud SQL instance not found"
            return 1
            ;;
        *)
            print_status "WARNING" "Cloud SQL instance status: $status"
            ;;
    esac
    
    # Get additional instance info
    local tier=$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format="value(settings.tier)" 2>/dev/null)
    local version=$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format="value(databaseVersion)" 2>/dev/null)
    local region=$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format="value(region)" 2>/dev/null)
    
    echo "  Instance ID: $INSTANCE_NAME"
    echo "  Tier: $tier"
    echo "  Version: $version"
    echo "  Region: $region"
}

check_connectivity() {
    print_section "Database Connectivity"
    
    # Check if database exists
    local db_exists=$(gcloud sql databases list --instance=$INSTANCE_NAME --project=$PROJECT_ID --format="value(name)" --filter="name=wordpress" 2>/dev/null || echo "")
    
    if [ "$db_exists" == "wordpress" ]; then
        print_status "OK" "WordPress database exists"
    else
        print_status "ERROR" "WordPress database not found"
    fi
    
    # Check proxy connection (if running on proxy VM)
    if command -v mysql &> /dev/null; then
        if timeout 5 mysql -h 127.0.0.1 -u root -p"$DB_PASSWORD" -e "SELECT 1;" &>/dev/null; then
            print_status "OK" "Proxy connection successful"
        else
            print_status "WARNING" "Cannot test proxy connection (password required)"
        fi
    else
        print_status "WARNING" "MySQL client not installed, cannot test connections"
    fi
}

check_proxy_status() {
    print_section "Cloud SQL Proxy Status"
    
    # Check if proxy process is running
    if pgrep -f "cloud_sql_proxy" > /dev/null; then
        print_status "OK" "Cloud SQL Proxy is running"
        
        # Get proxy process info
        local proxy_pid=$(pgrep -f "cloud_sql_proxy")
        local proxy_cmd=$(ps -p $proxy_pid -o command --no-headers 2>/dev/null || echo "Unknown")
        echo "  PID: $proxy_pid"
        echo "  Command: $proxy_cmd"
        
        # Check if proxy is listening on port 3306
        if netstat -ln 2>/dev/null | grep -q ":3306 "; then
            print_status "OK" "Proxy listening on port 3306"
        else
            print_status "WARNING" "Proxy may not be listening on port 3306"
        fi
    else
        print_status "ERROR" "Cloud SQL Proxy is not running"
    fi
    
    # Check systemd service if available
    if systemctl list-unit-files --type=service | grep -q "cloud-sql-proxy"; then
        local service_status=$(systemctl is-active cloud-sql-proxy 2>/dev/null || echo "inactive")
        if [ "$service_status" == "active" ]; then
            print_status "OK" "Cloud SQL Proxy service is active"
        else
            print_status "ERROR" "Cloud SQL Proxy service is $service_status"
        fi
    fi
}

check_compute_instances() {
    print_section "Compute Engine Instances"
    
    local instances=("wordpress-proxy" "wordpress-private-ip")
    
    for instance in "${instances[@]}"; do
        local status=$(gcloud compute instances describe $instance --zone=$REGION-a --project=$PROJECT_ID --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
        
        case $status in
            "RUNNING")
                print_status "OK" "$instance is running"
                local external_ip=$(gcloud compute instances describe $instance --zone=$REGION-a --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
                echo "  External IP: $external_ip"
                ;;
            "STOPPED")
                print_status "ERROR" "$instance is stopped"
                ;;
            "NOT_FOUND")
                print_status "ERROR" "$instance not found"
                ;;
            *)
                print_status "WARNING" "$instance status: $status"
                ;;
        esac
    done
}

check_wordpress_health() {
    print_section "WordPress Health Check"
    
    # Get external IPs
    local proxy_ip=$(gcloud compute instances describe wordpress-proxy --zone=$REGION-a --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
    local private_ip=$(gcloud compute instances describe wordpress-private-ip --zone=$REGION-a --project=$PROJECT_ID --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
    
    if [ -n "$proxy_ip" ]; then
        if timeout 10 curl -s "http://$proxy_ip" > /dev/null; then
            print_status "OK" "WordPress (proxy) is accessible at http://$proxy_ip"
        else
            print_status "ERROR" "WordPress (proxy) is not accessible"
        fi
    fi
    
    if [ -n "$private_ip" ]; then
        if timeout 10 curl -s "http://$private_ip" > /dev/null; then
            print_status "OK" "WordPress (private IP) is accessible at http://$private_ip"
        else
            print_status "ERROR" "WordPress (private IP) is not accessible"
        fi
    fi
}

show_resource_usage() {
    print_section "Resource Usage"
    
    # Cloud SQL metrics
    echo "Fetching Cloud SQL metrics..."
    
    # CPU utilization
    local cpu_usage=$(gcloud monitoring metrics list --filter="metric.type=cloudsql.googleapis.com/database/cpu/utilization" --project=$PROJECT_ID --format="value(metricDescriptor.displayName)" 2>/dev/null | head -1)
    
    if [ -n "$cpu_usage" ]; then
        echo "  CPU monitoring available"
    else
        echo "  CPU metrics not available or monitoring not enabled"
    fi
    
    # Memory utilization
    echo "  Memory metrics available through Cloud Monitoring"
    
    # Connection count
    echo "  Connection metrics available through Cloud Monitoring"
    
    echo ""
    echo "To view detailed metrics, use:"
    echo "  gcloud monitoring metrics list --filter='cloudsql' --project=$PROJECT_ID"
}

show_logs() {
    print_section "Recent Logs"
    
    echo "Cloud SQL error logs (last 10 lines):"
    gcloud sql operations list --instance=$INSTANCE_NAME --project=$PROJECT_ID --limit=5 --format="table(operationType,status,startTime,error[].message)" 2>/dev/null || echo "  No recent operations found"
    
    echo ""
    echo "To view detailed logs:"
    echo "  gcloud logging read 'resource.type=cloudsql_database' --project=$PROJECT_ID --limit=20"
}

troubleshooting_tips() {
    print_section "Troubleshooting Tips"
    
    echo "Common issues and solutions:"
    echo ""
    echo "1. Proxy connection refused:"
    echo "   - Check if proxy is running: pgrep -f cloud_sql_proxy"
    echo "   - Restart proxy: sudo systemctl restart cloud-sql-proxy"
    echo "   - Check logs: sudo journalctl -u cloud-sql-proxy -f"
    echo ""
    echo "2. WordPress can't connect to database:"
    echo "   - Verify database credentials in wp-config.php"
    echo "   - Check if wordpress database exists"
    echo "   - Test connection: mysql -h 127.0.0.1 -u root -p"
    echo ""
    echo "3. Cloud SQL instance not accessible:"
    echo "   - Check instance status: gcloud sql instances describe $INSTANCE_NAME"
    echo "   - Verify network configuration"
    echo "   - Check IAM permissions"
    echo ""
    echo "4. Performance issues:"
    echo "   - Monitor CPU/Memory usage in Cloud Console"
    echo "   - Check slow query logs"
    echo "   - Consider scaling instance tier"
}

show_useful_commands() {
    print_section "Useful Commands"
    
    echo "Cloud SQL management:"
    echo "  gcloud sql instances list --project=$PROJECT_ID"
    echo "  gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID"
    echo "  gcloud sql databases list --instance=$INSTANCE_NAME --project=$PROJECT_ID"
    echo ""
    echo "Proxy management:"
    echo "  sudo systemctl status cloud-sql-proxy"
    echo "  sudo systemctl restart cloud-sql-proxy"
    echo "  sudo journalctl -u cloud-sql-proxy -f"
    echo ""
    echo "Database operations:"
    echo "  mysql -h 127.0.0.1 -u root -p"
    echo "  gcloud sql connect $INSTANCE_NAME --user=root --project=$PROJECT_ID"
    echo ""
    echo "Monitoring:"
    echo "  gcloud monitoring metrics list --filter='cloudsql' --project=$PROJECT_ID"
    echo "  gcloud logging read 'resource.type=cloudsql_database' --project=$PROJECT_ID"
}

# Main function
main() {
    print_header
    get_project_id
    
    echo "Project: $PROJECT_ID"
    echo "Instance: $INSTANCE_NAME"
    echo "Region: $REGION"
    
    check_cloud_sql_status
    check_connectivity
    check_proxy_status
    check_compute_instances
    check_wordpress_health
    show_resource_usage
    show_logs
    troubleshooting_tips
    show_useful_commands
    
    echo -e "\n${GREEN}Monitoring complete!${NC}"
}

# Handle command line arguments
case "${1:-}" in
    "status")
        get_project_id
        check_cloud_sql_status
        ;;
    "proxy")
        check_proxy_status
        ;;
    "wordpress")
        get_project_id
        check_wordpress_health
        ;;
    "logs")
        get_project_id
        show_logs
        ;;
    *)
        main
        ;;
esac