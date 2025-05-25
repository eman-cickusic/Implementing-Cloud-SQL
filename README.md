# Implementing Cloud SQL

This repository contains the complete implementation guide and scripts for connecting WordPress applications to Google Cloud SQL using both external proxy connections and private IP connections.

## Video

https://youtu.be/sSaeK2wiUkc


## Overview

This lab demonstrates how to:
- Create and configure a Cloud SQL MySQL database
- Set up secure connections using Cloud SQL Proxy
- Connect applications via Private IP for enhanced performance and security
- Deploy WordPress applications with different connection methods

## Architecture

The final implementation includes:
- 1 Cloud SQL MySQL 5.7 instance (`wordpress-db`)
- 2 Compute Engine VMs running WordPress
- 2 different connection methods (proxy and private IP)

```
[WordPress App 1] ---> [Cloud SQL Proxy] ---> [Cloud SQL Instance]
[WordPress App 2] ---> [Private IP] --------> [Cloud SQL Instance]
```

## Prerequisites

- Google Cloud Platform account
- Project with billing enabled
- Required APIs enabled:
  - Cloud SQL Admin API
  - Compute Engine API
  - Service Networking API

## Quick Start

1. Clone this repository
2. Run the setup script: `./scripts/setup.sh`
3. Follow the configuration steps in the detailed guide below

## Detailed Implementation Guide

### Task 1: Create Cloud SQL Database

1. Navigate to **SQL** in the Google Cloud Console
2. Click **Create instance** → **Choose MySQL**
3. Configure the instance:
   ```
   Instance ID: wordpress-db
   Root password: [YOUR_SECURE_PASSWORD]
   Cloud SQL edition: Enterprise
   Region: [YOUR_PREFERRED_REGION]
   Database Version: MySQL 5.7
   ```

4. Configure machine specifications:
   - **Machine type**: Dedicated core, 1 vCPU, 3.75 GB
   - **Storage**: SSD, 10GB (with automatic increase enabled)

5. Enable Private IP:
   - Select **Private IP** in Connections
   - Choose **default** network
   - Click **Set up Connection** → **Enable API** → **Use automatically allocated IP range**

6. Click **Create Instance**

### Task 2: Configure Proxy on Virtual Machine

#### Setup Cloud SQL Proxy

SSH into the `wordpress-proxy` VM and run:

```bash
# Download and setup Cloud SQL Proxy
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy

# Set connection name (replace with your actual connection name)
export SQL_CONNECTION=[PROJECT_ID]:[REGION]:wordpress-db

# Start the proxy
./cloud_sql_proxy -instances=$SQL_CONNECTION=tcp:3306 &
```

#### Create WordPress Database

In the Cloud Console:
1. Go to **SQL** → **wordpress-db** → **Databases**
2. Click **Create database**
3. Database name: `wordpress`
4. Click **Create**

### Task 3: Connect Application via Proxy

1. Get the external IP of `wordpress-proxy`:
   ```bash
   curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip
   ```

2. Open browser to the external IP address
3. Configure WordPress with these settings:
   ```
   Database Name: wordpress
   Username: root
   Password: [YOUR_ROOT_PASSWORD]
   Database Host: 127.0.0.1
   ```

4. Complete the WordPress installation

### Task 4: Connect via Private IP

1. Note the private IP address of your Cloud SQL instance
2. Access the `wordpress-private-ip` VM via its external IP
3. Configure WordPress with these settings:
   ```
   Database Name: wordpress
   Username: root
   Password: [YOUR_ROOT_PASSWORD]
   Database Host: [SQL_PRIVATE_IP_ADDRESS]
   ```

4. Complete the installation

## Security Best Practices

- **Principle of Least Privilege**: VMs have minimal required permissions
- **Network Security**: Firewall rules restrict access to necessary ports only
- **Private IP**: Use private connections when VMs are in the same VPC
- **Proxy Connections**: Use Cloud SQL Proxy for external connections

## Performance Considerations

- **Private IP Connections**: Lower latency, higher security
- **Machine Configuration**: Right-size your Cloud SQL instance
- **Storage Type**: SSD for better performance, HDD for cost savings
- **Network Throughput**: Each vCPU provides up to 250 MB/s throughput

## Configuration Files

- [`scripts/setup.sh`](./scripts/setup.sh) - Automated setup script
- [`config/cloud-sql-config.yaml`](./config/cloud-sql-config.yaml) - Cloud SQL configuration
- [`scripts/proxy-setup.sh`](./scripts/proxy-setup.sh) - Proxy configuration script
- [`config/wordpress-config.php`](./config/wordpress-config.php) - WordPress configuration template

## Troubleshooting

### Common Issues

1. **Connection refused errors**
   - Verify Cloud SQL instance is running
   - Check firewall rules
   - Confirm proxy is listening on correct port

2. **Database connection timeouts**
   - Verify private IP setup is complete
   - Check VPC network configuration
   - Confirm database credentials

3. **WordPress installation fails**
   - Ensure `wordpress` database exists
   - Verify user permissions
   - Check PHP extensions are installed

### Useful Commands

```bash
# Check proxy status
ps aux | grep cloud_sql_proxy

# Test database connection
mysql -h 127.0.0.1 -u root -p

# View Cloud SQL logs
gcloud sql operations list --instance=wordpress-db
```

## Cost Optimization

- Use **Shared-core** instances for development/testing
- Enable **automatic storage increase** to avoid outages
- Consider **HDD storage** for infrequently accessed data
- Monitor usage with **Cloud Monitoring**

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Resources

- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Cloud SQL Proxy Documentation](https://cloud.google.com/sql/docs/mysql/sql-proxy)
- [WordPress on Google Cloud](https://cloud.google.com/community/tutorials/run-wordpress-on-appengine-standard)

## Support

For issues related to this implementation, please open an issue in this repository.

For Google Cloud support, visit the [Google Cloud Support page](https://cloud.google.com/support).
