<?php
/**
 * WordPress Configuration Template for Google Cloud SQL
 * 
 * This template provides configuration for both proxy and private IP connections
 * Copy this file to wp-config.php in your WordPress installation
 */

// ** Database Connection Type ** //
// Set this to 'proxy' for Cloud SQL Proxy connection or 'private' for Private IP
define('DB_CONNECTION_TYPE', 'proxy'); // Change to 'private' for private IP connection

// ** MySQL settings ** //
if (DB_CONNECTION_TYPE === 'proxy') {
    // Configuration for Cloud SQL Proxy connection
    define('DB_NAME', 'wordpress');
    define('DB_USER', 'root');
    define('DB_PASSWORD', 'YOUR_ROOT_PASSWORD'); // Replace with your actual password
    define('DB_HOST', '127.0.0.1:3306'); // Proxy listens on localhost
    
} else {
    // Configuration for Private IP connection
    define('DB_NAME', 'wordpress');
    define('DB_USER', 'root');
    define('DB_PASSWORD', 'YOUR_ROOT_PASSWORD'); // Replace with your actual password
    define('DB_HOST', 'YOUR_PRIVATE_IP:3306'); // Replace with your Cloud SQL private IP
}

/** Database Charset to use in creating database tables. */
define('DB_CHARSET', 'utf8mb4');

/** The Database Collate type. Don't change this if in doubt. */
define('DB_COLLATE', 'utf8mb4_unicode_ci');

/**#@+
 * Authentication Unique Keys and Salts.
 * 
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 */
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

/**#@-*/

/**
 * WordPress Database Table prefix.
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 */
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

/**
 * Google Cloud specific configurations
 */

// Disable file editing in WordPress admin
define('DISALLOW_FILE_EDIT', true);

// Force SSL if using HTTPS load balancer
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    define('FORCE_SSL_ADMIN', true);
}

// WordPress URLs - adjust if using load balancer
// define('WP_HOME', 'https://your-domain.com');
// define('WP_SITEURL', 'https://your-domain.com');

// Memory limit
ini_set('memory_limit', '256M');

// File upload settings
define('WP_MEMORY_LIMIT', '256M');
define('MAX_FILE_SIZE', 33554432); // 32MB

/**
 * Cloud SQL Connection Optimization
 */

// Increase MySQL timeout for Cloud SQL
define('DB_TIMEOUT', 30);

// Connection retry settings
define('DB_RETRY_ATTEMPTS', 3);
define('DB_RETRY_DELAY', 1); // seconds

/**
 * WordPress Cache Configuration
 */

// Enable object caching if using Memcached/Redis
// define('WP_CACHE', true);

// Session handling for load-balanced environments
// define('WP_SESSION_TIMEOUT', 3600);

/**
 * Security Headers
 */
if (!headers_sent()) {
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: SAMEORIGIN');
    header('X-XSS-Protection: 1; mode=block');
}

/**
 * Multisite Configuration (if needed)
 */
// define('WP_ALLOW_MULTISITE', true);
// define('MULTISITE', true);
// define('SUBDOMAIN_INSTALL', false);
// define('DOMAIN_CURRENT_SITE', 'your-domain.com');
// define('PATH_CURRENT_SITE', '/');
// define('SITE_ID_CURRENT_SITE', 1);
// define('BLOG_ID_CURRENT_SITE', 1);

/**
 * Custom error handling for Cloud SQL connections
 */
function handle_db_connection_error($error) {
    error_log('Database connection error: ' . $error);
    
    // Custom error page for production
    if (!WP_DEBUG) {
        wp_die('Database connection error. Please try again later.', 'Database Error', array('response' => 500));
    }
}

// Set custom error handler
// set_error_handler('handle_db_connection_error');

/**
 * Performance optimizations
 */

// Disable WordPress cron if using external cron
// define('DISABLE_WP_CRON', true);

// Increase autosave interval
define('AUTOSAVE_INTERVAL', 300); // 5 minutes

// Limit post revisions
define('WP_POST_REVISIONS', 5);

// Empty trash automatically
define('EMPTY_TRASH_DAYS', 7);

/**
 * Google Cloud Storage (if using)
 */
// define('GOOGLE_CLOUD_STORAGE_BUCKET', 'your-bucket-name');
// define('GOOGLE_CLOUD_STORAGE_KEY_FILE', '/path/to/service-account.json');

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';

/**
 * Custom functions for Cloud SQL monitoring
 */
function log_db_queries() {
    if (defined('SAVEQUERIES') && SAVEQUERIES) {
        global $wpdb;
        error_log('Total DB queries: ' . count($wpdb->queries));
        error_log('Total query time: ' . array_sum(array_column($wpdb->queries, 1)));
    }
}

// Log database queries on shutdown (for debugging)
if (WP_DEBUG) {
    add_action('shutdown', 'log_db_queries');
}

/**
 * Health check endpoint for load balancers
 */
function custom_health_check() {
    if ($_SERVER['REQUEST_URI'] === '/health-check') {
        // Test database connection
        global $wpdb;
        $result = $wpdb->get_var("SELECT 1");
        
        if ($result === '1') {
            http_response_code(200);
            echo 'OK';
        } else {
            http_response_code(503);
            echo 'Database connection failed';
        }
        exit;
    }
}

add_action('init', 'custom_health_check');
?>