#!/bin/bash

################################################################################
# install.sh - Debian automated installation script
# Purpose: Automate installation and configuration of services on Debian/Ubuntu
# Supported: Debian 10+, Ubuntu 18.04+
# Usage: sudo bash install.sh
# 
# Features:
#   - Idempotent: Safe to run multiple times
#   - Package checks: Only installs missing packages
#   - Conditional installation: SELF_BACKEND controls Nginx installation
#   - Complete logging: All operations logged to /tmp/install.log
################################################################################

set -e

# ============================================================================
# Global variables
# ============================================================================
PROTOCOL_TYPE=""
SERVER_ADDR=""
FAKE_SITE="www.microsoft.com"      # Default fake site for reality
FAKE_SITE_PORT="443"                # Default fake site port
LOG_FILE="/tmp/install.log"
SELF_BACKEND="${SELF_BACKEND:-false}"  # Set to 'true' to install Nginx, default is 'false'

# ============================================================================
# Color definitions
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Logging helpers
# ============================================================================
log_info() {
    local msg="[INFO] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_success() {
    local msg="[✓] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_warn() {
    local msg="[WARN] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg="[ERROR] $1"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

# ============================================================================
# System checks
# ============================================================================
check_system() {
    # Initialize log file
    : > "$LOG_FILE"
    log_info "Installation started (SELF_BACKEND=$SELF_BACKEND)"
    log_info "Checking system environment..."

    # ensure running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges"
        echo "Run: sudo bash install.sh"
        exit 1
    fi

    # ensure Debian/Ubuntu
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script supports only Debian/Ubuntu systems"
        exit 1
    fi

    log_success "System check passed"
}

# ============================================================================
# Update package manager
# ============================================================================
update_package_manager() {
    log_info "Updating package indices..."
    if apt-get update >> "$LOG_FILE" 2>&1; then
        log_success "Package indices updated"
    else
        log_error "Failed to update package indices"
        exit 1
    fi
}

# ============================================================================
# Install required packages
# ============================================================================
install_dependencies() {
    log_info "Installing dependencies..."

    local packages=(
        "curl"
        "wget"
        "ca-certificates"
        "openssl"
        "jq"
        "qrencode"
    )

    # Add nginx only if SELF_BACKEND is true
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        packages+=("nginx")
        log_info "SELF_BACKEND is true, nginx will be installed"
    else
        log_info "SELF_BACKEND is false, nginx installation skipped"
    fi

    for package in "${packages[@]}"; do
        # Check if package is already installed
        if dpkg -l | grep -qw "$package" 2>/dev/null; then
            log_info "$package already installed (skipped)"
        else
            log_info "Installing $package..."
            if apt-get install -y "$package" >> "$LOG_FILE" 2>&1; then
                log_success "$package installed successfully"
            else
                log_error "Failed to install $package"
                exit 1
            fi
        fi
    done

    log_success "All dependencies installed"
}

# ============================================================================
# Create directory structure
# ============================================================================
create_directories() {
    log_info "Creating directory structure..."

    local dirs=(
        "/var/www/html"
        "/var/log/nginx"
        "/etc/nginx/ssl"
        "/etc/sing-box"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        else
            log_info "Directory already exists: $dir"
        fi
    done

    log_success "Directory structure ready"
}

# ============================================================================
# Install configuration files
# ============================================================================
install_config_files() {
    log_info "Installing configuration files..."

    # determine script directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Only install nginx config if SELF_BACKEND is true
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        # nginx config
        if [[ -f "$script_dir/nginx/nginx.conf" ]]; then
            log_info "Installing nginx configuration..."
            \cp -f "$script_dir/nginx/nginx.conf" /etc/nginx/nginx.conf >> "$LOG_FILE" 2>&1
            
            if [[ -d "$script_dir/nginx/conf.d" ]] && [[ $(ls -A "$script_dir/nginx/conf.d" 2>/dev/null) ]]; then
                rm -rf /etc/nginx/conf.d/*
                cp "$script_dir/nginx/conf.d/"* /etc/nginx/conf.d/ >> "$LOG_FILE" 2>&1
                read -p "Replace placeholder domain in nginx configs with PLACEHOLDER_DOMAIN? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then 
                    read -p "Enter domain to replace (default: your_domain.com): " -r domain_input
                    domain_input=${domain_input:-your_domain.com}
                    sed -i "s/PLACEHOLDER_DOMAIN/$domain_input/g" /etc/nginx/conf.d/mask.conf
                    log_info "Updated domain: $domain_input"
                fi
                chmod 644 /etc/nginx/conf.d/*
            fi
            chmod 644 /etc/nginx/nginx.conf
            log_success "nginx configuration installed"
        else
            log_warn "nginx config not found: $script_dir/nginx/nginx.conf"
        fi

        # website files
        if [[ -d "$script_dir/nginx/html" ]]; then
            log_info "Installing website files..."
            cp -r "$script_dir/nginx/html"/* /var/www/html/ 2>/dev/null || true
            chmod -R 755 /var/www/html
            log_success "Website files installed"
        else
            log_warn "Website directory not found: $script_dir/nginx/html"
        fi
    else
        log_info "SELF_BACKEND is false, skipping nginx configuration installation"
    fi

    # sing-box configs
    if [[ -d "$script_dir/sing-box" ]]; then
        log_info "Installing sing-box configuration..."
        cp -r "$script_dir/sing-box"/1.13.8/* /etc/sing-box/ 2>/dev/null || true
        chmod -R 755 /etc/sing-box
        log_success "sing-box configuration installed"
    else
        log_warn "sing-box directory not found: $script_dir/sing-box"
    fi
}

# ============================================================================
# Install SSL certificates (if present)
# ============================================================================
setup_ssl_certificates() {
    if [[ "${SELF_BACKEND}" != "true" ]]; then
        log_info "SELF_BACKEND is false, skipping SSL certificates setup"
        return 0
    fi

    log_info "Checking for SSL certificates..."

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -d "$script_dir/nginx/ssl" ]] && [[ $(ls -A "$script_dir/nginx/ssl" 2>/dev/null) ]]; then
        log_info "Installing SSL certificates..."
        cp "$script_dir/nginx/ssl"/* /etc/nginx/ssl/ >> "$LOG_FILE" 2>&1
        chmod 600 /etc/nginx/ssl/*
        log_success "SSL certificates installed"
    else
        log_info "No SSL certificates found. You can add them later to /etc/nginx/ssl"
    fi
}

# ============================================================================
# Validate nginx configuration
# ============================================================================
validate_nginx_config() {
    if [[ "${SELF_BACKEND}" != "true" ]]; then
        log_info "SELF_BACKEND is false, skipping nginx validation"
        return 0
    fi

    if ! command -v nginx &> /dev/null; then
        log_info "nginx not installed, skipping validation"
        return 0
    fi

    log_info "Validating nginx configuration..."

    if ! nginx -t >> "$LOG_FILE" 2>&1; then
        log_error "nginx configuration test failed. Please check configuration files"
    else
        log_success "nginx configuration OK"
    fi
}

# ============================================================================
# Configure nginx service
# ============================================================================
setup_nginx_service() {
    if [[ "${SELF_BACKEND}" != "true" ]]; then
        log_info "SELF_BACKEND is false, skipping nginx service setup"
        return 0
    fi

    if ! command -v nginx &> /dev/null; then
        log_warn "nginx not installed, skipping service configuration"
        return 0
    fi

    log_info "Configuring nginx service..."

    # enable nginx on boot
    if systemctl enable nginx >> "$LOG_FILE" 2>&1; then
        log_info "nginx enabled for autostart"
    else
        log_warn "Failed to enable nginx autostart"
    fi

    # restart nginx
    if systemctl restart nginx >> "$LOG_FILE" 2>&1; then
        log_success "nginx service configured and started"
    else
        log_error "Failed to start nginx"
        return 1
    fi
}

# ============================================================================
# Create sing-box user and directories
# ============================================================================
create_sing_box_user() {
    log_info "Creating sing-box user and directories..."

    # check for existing user
    if id "sing-box" &>/dev/null; then
        log_info "sing-box user already exists (skipped)"
    else
        log_info "Creating sing-box system user..."
        if useradd -r -s /bin/false -d /var/lib/sing-box -m -U sing-box >> "$LOG_FILE" 2>&1; then
            log_success "sing-box user created"
        else
            log_error "Failed to create sing-box user"
            return 1
        fi
    fi

    # create directories if not exist
    if [[ ! -d /var/lib/sing-box ]]; then
        mkdir -p /var/lib/sing-box
        log_info "Created /var/lib/sing-box"
    fi
    
    if [[ ! -d /etc/sing-box ]]; then
        mkdir -p /etc/sing-box
        log_info "Created /etc/sing-box"
    fi

    # set ownership and permissions
    chown -R sing-box:sing-box /var/lib/sing-box
    chown -R sing-box:sing-box /etc/sing-box
    chmod 755 /var/lib/sing-box
    chmod 755 /etc/sing-box
    
    log_success "sing-box user and directories ready"
}

# ============================================================================
# Install sing-box
# ============================================================================
install_sing_box() {
    log_info "Preparing to install sing-box..."

    # choose protocol
    echo ""
    echo "Select protocol type:"
    echo "  1) AnyTLS"
    echo "  2) VLESS"
    read -p "Choose protocol (1 or 2, default: 1): " -r protocol_choice
    protocol_choice=${protocol_choice:-1}

    if [[ "$protocol_choice" == "2" ]]; then
        local protocol_type="vless"
        log_info "Selected protocol: VLESS"
        echo -e "${GREEN}Configuring for VLESS${NC}"
    else
        local protocol_type="anytls"
        log_info "Selected protocol: AnyTLS"
        echo -e "${GREEN}Configuring for AnyTLS${NC}"
    fi
    echo ""

    # check existing installation
    if command -v sing-box &> /dev/null; then
        local current_version=$(sing-box version 2>/dev/null | head -n1)
        log_warn "sing-box already installed (version: $current_version)"
        read -p "Reinstall or update? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping sing-box installation (already installed)"
            PROTOCOL_TYPE="$protocol_type"
            return 0
        fi
    fi

    # version selection
    local version="1.13.8"
    read -p "Enter sing-box version to install (default: ${version}): " -r version_input
    if [[ -n "$version_input" ]]; then
        version="$version_input"
    fi

    log_info "Installing sing-box (version: $version)..."

    # run official installer
    if [[ "$version" == "latest" ]]; then
        if curl -fsSL https://sing-box.app/install.sh | sh >> "$LOG_FILE" 2>&1; then
            log_info "sing-box installer executed"
        else
            log_error "sing-box installation failed"
            return 1
        fi
    else
        if curl -fsSL https://sing-box.app/install.sh | sh -s -- --version "$version" >> "$LOG_FILE" 2>&1; then
            log_info "sing-box installer executed"
        else
            log_error "sing-box installation failed"
            return 1
        fi
    fi

    # verify installation
    if command -v sing-box &> /dev/null; then
        local installed_version=$(sing-box version 2>/dev/null | head -n1)
        log_success "sing-box installed (version: $installed_version)"
    else
        log_error "sing-box executable not found after installation"
        return 1
    fi

    log_info "Generating Reality keypair..."
    if sing-box generate reality-keypair > /etc/sing-box/reality-keypair.txt 2>> "$LOG_FILE"; then
        log_success "Reality keypair generated"
    else
        log_error "Failed to generate Reality keypair"
        return 1
    fi

    log_info "Generating UUID..."
    if sing-box generate uuid > /etc/sing-box/uuid.txt 2>> "$LOG_FILE"; then
        log_success "UUID generated"
    else
        log_error "Failed to generate UUID"
        return 1
    fi
    
    chmod 600 /etc/sing-box/reality-keypair.txt /etc/sing-box/uuid.txt

    short_id=$(openssl rand -hex 8)
    private_key=$(cat /etc/sing-box/reality-keypair.txt | grep "PrivateKey" | awk -F': ' '{print $2}')
    public_key=$(cat /etc/sing-box/reality-keypair.txt | grep "PublicKey" | awk -F': ' '{print $2}')
    uuid=$(cat /etc/sing-box/uuid.txt)
    
    read -p "Enter server name (default: your_server_name): " -r server_name_input
    server_name="${server_name_input:-your_server_name}"
    log_info "Server name set to: $server_name"

    # Configure fake site for reality
    echo ""
    echo -e "${YELLOW}[Reality Configuration]${NC}"
    echo "Configure masquerade site for Reality handshake:"
    echo "  1) Use default (www.microsoft.com:443)"
    echo "  2) Use localhost (127.0.0.1:8443)"
    echo ""
    read -p "Choose fake site (1 or 2, default: 1): " -r fake_site_choice
    fake_site_choice=${fake_site_choice:-1}
    
    if [[ "$fake_site_choice" == "2" ]]; then
        fake_site="127.0.0.1"
        fake_site_port="8443"
        log_info "Fake site set to: $fake_site:$fake_site_port (localhost)"
    else
        fake_site="www.microsoft.com"
        fake_site_port="443"
        log_info "Fake site set to: $fake_site:$fake_site_port (default)"
    fi
    echo ""

    rm -rf /etc/sing-box/config.json
    
    # configure according to protocol
    if [[ "$protocol_type" == "vless" ]]; then
        echo -e "${YELLOW}[VLESS Configuration]${NC}"
        echo "  • UUID: $uuid"
        echo "  • Server name: $server_name"
        echo "  • Reality short ID: $short_id"
        echo "  • Fake site: $fake_site:$fake_site_port"
        ln -sf /etc/sing-box/vless.json /etc/sing-box/config.json
        log_info "VLESS configuration linked"
    else
        your_secure_password=$(openssl rand -hex 16)
        echo -e "${YELLOW}[AnyTLS Configuration]${NC}"
        echo "  • Username: admin007"
        echo "  • Password: $your_secure_password"
        echo "  • Fake site: $fake_site:$fake_site_port"
        ln -sf /etc/sing-box/anyTLS.json /etc/sing-box/config.json
        sed -i "s/PLACEHOLDER_PASSWORD/$your_secure_password/g" /etc/sing-box/config.json
        log_info "AnyTLS configuration linked with generated password"
    fi
    
    sed -i "s/PLACEHOLDER_SHORT_ID/$short_id/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_PRIVATE_KEY/$private_key/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_PUBLIC_KEY/$public_key/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_SERVER_NAME/$server_name/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_UUID/$uuid/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_FAKE_SITE/$fake_site/g" /etc/sing-box/config.json
    sed -i "s/PLACEHOLDER_FAKE_SITE_PORT/$fake_site_port/g" /etc/sing-box/config.json
    log_success "sing-box configuration placeholders updated"

    # save global variables for later use
    PROTOCOL_TYPE="$protocol_type"
    SERVER_ADDR="$server_name"

    # configure sing-box service
    setup_sing_box_service
}

# ============================================================================
# Generate subscription links
# ============================================================================
generate_subscription() {
    log_info "Generating subscription link..."

    if [[ ! -f /etc/sing-box/config.json ]]; then
        log_error "Config file not found: /etc/sing-box/config.json"
        return 1
    fi

    if [[ "$PROTOCOL_TYPE" == "vless" ]]; then
        # read params from VLESS config
        local uuid=$(jq -r '.inbounds[0].users[0].uuid' /etc/sing-box/config.json 2>/dev/null)
        local flow=$(jq -r '.inbounds[0].users[0].flow' /etc/sing-box/config.json 2>/dev/null)
        local port=$(jq -r '.inbounds[0].listen_port' /etc/sing-box/config.json 2>/dev/null)
        local sni=$(jq -r '.inbounds[0].tls.server_name' /etc/sing-box/config.json 2>/dev/null)
        local pbk=$(cat /etc/sing-box/reality-keypair.txt | grep "PublicKey" | awk -F': ' '{print $2}')
        local sid=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/sing-box/config.json 2>/dev/null)

        if [[ -z "$uuid" || -z "$port" ]]; then
            log_error "Failed to read VLESS parameters from config"
            return 1
        fi

        # build VLESS URI
        local vless_url="vless://${uuid}@${sni}?type=tcp&security=reality&pbk=${pbk}&sid=${sid}&sni=${sni}&fp=chrome#VLESS"

        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}VLESS Subscription Link${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Link: $vless_url"
        echo ""
        echo "Details:"
        echo "  • UUID: $uuid"
        echo "  • Server: $sni"
        echo "  • Port: $port"
        echo "  • Public key (pbk): $pbk"
        echo "  • Short ID (sid): $sid"
        echo "  • Flow: $flow"
        echo "  • Fake site (reality): $fake_site:$fake_site_port"
        echo ""

        # QR code
        if command -v qrencode &> /dev/null; then
            echo "$vless_url" | qrencode -t ANSI256
        fi

        # save to file
        echo "$vless_url" > /etc/sing-box/vless-subscription.txt
        log_success "VLESS subscription generated and saved to /etc/sing-box/vless-subscription.txt"

    else
        # read params from AnyTLS config
        local username=$(jq -r '.inbounds[0].users[0].name' /etc/sing-box/config.json 2>/dev/null)
        local password=$(jq -r '.inbounds[0].users[0].password' /etc/sing-box/config.json 2>/dev/null)
        local port=$(jq -r '.inbounds[0].listen_port' /etc/sing-box/config.json 2>/dev/null)
        local sni=$(jq -r '.inbounds[0].tls.server_name' /etc/sing-box/config.json 2>/dev/null)
        local pbk=$(cat /etc/sing-box/reality-keypair.txt | grep "PublicKey" | awk -F': ' '{print $2}')
        local sid=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /etc/sing-box/config.json 2>/dev/null)

        if [[ -z "$username" || -z "$password" || -z "$port" ]]; then
            log_error "Failed to read AnyTLS parameters from config"
            return 1
        fi

        # server address from global or fallback
        local server_addr="${SERVER_ADDR:-localhost}"

        # build AnyTLS URI
        local anytls_url="anytls://${username}:${password}@${server_addr}:${port}?sni=${sni}&pbk=${pbk}&sid=${sid}#SingBox-AnyTLS"

        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}AnyTLS Subscription Link${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Link: $anytls_url"
        echo ""
        echo "Details:"
        echo "  • Username: $username"
        echo "  • Password: $password"
        echo "  • Port: $port"
        echo "  • Server: $server_addr"
        echo "  • SNI: $sni"
        echo "  • Public key (pbk): $pbk"
        echo "  • Short ID (sid): $sid"
        echo "  • Fake site (reality): $fake_site:$fake_site_port"
        echo ""

        # QR code
        if command -v qrencode &> /dev/null; then
            echo "$anytls_url" | qrencode -t ANSI256
        fi

        # save to file
        echo "$anytls_url" > /etc/sing-box/anytls-subscription.txt
        log_success "AnyTLS subscription generated and saved to /etc/sing-box/anytls-subscription.txt"
    fi

    echo ""
}

# ============================================================================
setup_sing_box_service() {
    log_info "Configuring sing-box systemd service..."

    # check for config directory
    if [[ ! -d /etc/sing-box ]]; then
        log_warn "Directory /etc/sing-box not found, skipping service configuration"
        return 0
    fi

    # create systemd service file
    local service_file="/etc/systemd/system/sing-box.service"

    if [[ ! -f "$service_file" ]]; then
        log_info "Creating sing-box systemd service file..."
        cat > "$service_file" << 'SYSTEMD_EOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target network-online.target

[Service]
User=sing-box
StateDirectory=sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/bin/sing-box -D /var/lib/sing-box -c /etc/sing-box/config.json run
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity
Type=simple

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
        chmod 644 "$service_file"
        systemctl daemon-reload >> "$LOG_FILE" 2>&1
        log_success "sing-box service file created"
    else
        log_info "sing-box service file already exists (skipped)"
    fi

    # Setup log file if configured
    if [[ -f /etc/sing-box/config.json ]]; then
        local log_file=$(jq -r '.log.output' /etc/sing-box/config.json 2>/dev/null || echo "")
        if [[ -n "$log_file" ]]; then
            touch "$log_file" 2>/dev/null || true
            chown sing-box:sing-box "$log_file" 2>/dev/null || true
            log_info "Log file configured: $log_file"
        fi
    fi
    
    chown root:root "$service_file" 2>/dev/null || true

    # ask whether to enable/start service
    read -p "Enable and start sing-box service? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Enabling sing-box autostart..."
        if systemctl enable sing-box >> "$LOG_FILE" 2>&1; then
            log_info "sing-box enabled for autostart"
        else
            log_warn "Failed to enable sing-box autostart"
        fi

        log_info "Starting sing-box service..."
        if systemctl start sing-box >> "$LOG_FILE" 2>&1; then
            log_info "sing-box start command sent"
            sleep 2
            if systemctl is-active --quiet sing-box; then
                log_success "sing-box service is running"
            else
                log_error "sing-box service failed to run"
                log_info "Run 'journalctl -u sing-box -n 50' to view logs"
                return 1
            fi
        else
            log_error "Failed to start sing-box service"
            log_info "Check configuration under /etc/sing-box/"
            return 1
        fi
    else
        log_info "sing-box service start skipped by user"
    fi
}

# ============================================================================
# Set permissions
# ============================================================================
setup_permissions() {
    log_info "Setting file permissions..."

    if [[ "${SELF_BACKEND}" == "true" ]]; then
        # web root ownership
        chown -R www-data:www-data /var/www/html 2>/dev/null || true
        chmod -R 755 /var/www/html
        log_info "Web root permissions set"

        # nginx logs
        chown -R www-data:www-data /var/log/nginx 2>/dev/null || true
        chmod -R 755 /var/log/nginx
        log_info "Nginx logs permissions set"

        # configuration files
        chmod 644 /etc/nginx/nginx.conf 2>/dev/null || true
        if [[ -f /etc/nginx/ssl/* ]]; then
            chmod 600 /etc/nginx/ssl/* 2>/dev/null || true
        fi
        log_info "Nginx config permissions set"
    else
        log_info "SELF_BACKEND is false, skipping nginx permissions"
    fi

    log_success "Permissions configured"
}

# ============================================================================
# Show installation summary
# ============================================================================
# ============================================================================
# Show installation summary
# ============================================================================
show_summary() {
    log_info "Installation complete"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Key locations:"
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        echo "  • Web root: /var/www/html"
        echo "  • Nginx config: /etc/nginx/nginx.conf"
        echo "  • SSL certificates: /etc/nginx/ssl/"
        echo "  • Nginx logs: /var/log/nginx/"
    fi
    echo "  • Sing-box config: /etc/sing-box/"
    echo "  • Installation log: $LOG_FILE"
    echo ""
    echo "Configuration Summary:"
    echo "  • Protocol: $PROTOCOL_TYPE"
    echo "  • Fake site (Reality): $FAKE_SITE:$FAKE_SITE_PORT"
    echo ""
    echo "Useful commands:"
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        echo "  • Check nginx status: systemctl status nginx"
        echo "  • Restart nginx: systemctl restart nginx"
        echo "  • Reload nginx: systemctl reload nginx"
        echo "  • Tail nginx access log: tail -f /var/log/nginx/access.log"
    fi
    echo "  • Check sing-box status: systemctl status sing-box"
    echo "  • Restart sing-box: systemctl restart sing-box"
    echo "  • Tail sing-box logs: journalctl -u sing-box -f"
    echo "  • View installation logs: tail -f $LOG_FILE"
    echo ""
    echo "Next steps:"
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        echo "  1) If you need SSL, place certificates in /etc/nginx/ssl/"
        echo "  2) Adjust /etc/nginx/nginx.conf for your environment"
        echo "  3) Edit /etc/sing-box/config.json to tune sing-box"
        echo "  4) Run 'nginx -t' to validate nginx configuration"
        echo "  5) Run 'systemctl reload nginx' to apply nginx changes"
        echo "  6) Run 'systemctl restart sing-box' to restart sing-box"
        echo "  7) View subscription links: cat /etc/sing-box/*-subscription.txt"
    else
        echo "  1) Edit /etc/sing-box/config.json to tune sing-box"
        echo "  2) Run 'systemctl restart sing-box' to restart sing-box"
        echo "  3) View subscription links: cat /etc/sing-box/*-subscription.txt"
    fi
    echo ""
}


main() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}       Debian Automated Installation Script${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
    echo ""
    
    
    # Ask for confirmation before starting installation
    echo -e "${YELLOW}⚠️  This script will install and configure services on your system.${NC}"
    echo ""
    echo "About to install:"
    echo "  • curl, wget, ca-certificates, openssl, jq, qrencode"
    if [[ "${SELF_BACKEND}" == "true" ]]; then
        echo "  • nginx (reverse proxy)"
    fi
    echo "  • sing-box (proxy server)"
    echo ""
    read -p "Do you want to continue with the installation? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Installation cancelled by user${NC}"
        exit 0
    fi
    
    # Ask for SELF_BACKEND configuration
    echo -e "${YELLOW}[Configuration]${NC}"
    echo ""
    echo "Do you want to install Nginx as reverse proxy?"
    echo "  • YES (1): Install Nginx with sing-box"
    echo "  • NO (2):  Install only sing-box (recommended for minimal setup)"
    echo ""
    read -p "Choose option (1 or 2, default: 2): " -n 1 -r
    echo ""
    
    if [[ $REPLY == "1" ]]; then
        SELF_BACKEND="true"
        echo -e "${GREEN}✓ Nginx will be installed${NC}"
    else
        SELF_BACKEND="false"
        echo -e "${GREEN}✓ Nginx will NOT be installed${NC}"
    fi
    echo ""

    echo "Installation log: $LOG_FILE"
    echo ""
    
    check_system
    update_package_manager
    install_dependencies
    create_sing_box_user
    create_directories
    install_config_files
    setup_ssl_certificates
    validate_nginx_config
    setup_permissions
    setup_nginx_service
    install_sing_box
    
    if [[ -n "$PROTOCOL_TYPE" ]]; then
        generate_subscription
    fi
}

trap 'log_error "Installation failed at line $LINENO"; log_error "Check logs at $LOG_FILE"; exit 1' ERR
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
