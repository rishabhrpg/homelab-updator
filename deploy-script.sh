#!/bin/bash

# Deploy Script for Local Chat
# Triggered by GitHub webhook on new release
# Usage: ./deploy.sh <tarball_url> <tag_name>

set -e  # Exit on any error

# Configuration
PROJECT_DIR="/home/super/home-lab/local-chat/app"
APP_NAME="local-chat"
BACKUP_DIR="/home/super/backups"
LOG_DIR="${HOME}/logs"
LOG_FILE="${LOG_DIR}/deploy-${APP_NAME}.log"
TEMP_DIR="/tmp/deploy-${APP_NAME}"

# Arguments from webhook
TARBALL_URL="$1"
TAG_NAME="$2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Check if we can write to log file
if touch "$LOG_FILE" 2>/dev/null; then
    USE_LOG_FILE=true
else
    USE_LOG_FILE=false
    echo -e "${YELLOW}Warning: Cannot write to log file. Logging to stdout only.${NC}"
fi

# Logging functions
log() {
    local msg="${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo -e "$msg"
    if [ "$USE_LOG_FILE" = true ]; then
        echo -e "$1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

error() {
    local msg="${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    echo -e "$msg" >&2
    if [ "$USE_LOG_FILE" = true ]; then
        echo -e "ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

warning() {
    local msg="${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
    echo -e "$msg"
    if [ "$USE_LOG_FILE" = true ]; then
        echo -e "WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

info() {
    local msg="${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
    echo -e "$msg"
    if [ "$USE_LOG_FILE" = true ]; then
        echo -e "INFO: $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "🧹 Cleaned up temporary files"
    fi
}

# Main deployment process
main() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🚀 Starting deployment for $APP_NAME"
    log "🏷️  Tag: $TAG_NAME"
    log "📦 Tarball URL: $TARBALL_URL"
    if [ "$USE_LOG_FILE" = true ]; then
        log "📝 Log file: $LOG_FILE"
    fi
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Validate arguments
    if [ -z "$TARBALL_URL" ] || [ -z "$TAG_NAME" ]; then
        error "Missing required arguments: tarball_url and tag_name"
        error "Usage: $0 <tarball_url> <tag_name>"
        exit 1
    fi
    
    # Create temporary directory
    log "📁 Creating temporary directory..."
    mkdir -p "$TEMP_DIR"
    
    # Download tarball
    log "⬇️  Downloading release tarball..."
    if command -v curl &> /dev/null; then
        curl -L -o "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" || {
            error "Failed to download tarball"
            cleanup
            exit 1
        }
    elif command -v wget &> /dev/null; then
        wget -O "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" || {
            error "Failed to download tarball"
            cleanup
            exit 1
        }
    else
        error "Neither curl nor wget found. Cannot download tarball."
        cleanup
        exit 1
    fi
    log "✅ Tarball downloaded"
    
    # Extract tarball
    log "📦 Extracting tarball..."
    tar -xzf "$TEMP_DIR/release.tar.gz" -C "$TEMP_DIR" || {
        error "Failed to extract tarball"
        cleanup
        exit 1
    }
    
    # GitHub tarballs extract to a directory named like: owner-repo-commitsha
    # Find the extracted directory
    EXTRACTED_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    
    if [ -z "$EXTRACTED_DIR" ]; then
        error "Could not find extracted directory"
        cleanup
        exit 1
    fi
    
    log "✅ Tarball extracted to: $EXTRACTED_DIR"
    
    # Verify project directory exists
    if [ ! -d "$PROJECT_DIR" ]; then
        warning "Project directory does not exist. Creating: $PROJECT_DIR"
        mkdir -p "$PROJECT_DIR"
    fi
    
    # Create backup of current deployment
    if [ "$(ls -A $PROJECT_DIR 2>/dev/null)" ]; then
        log "💾 Creating backup of current deployment..."
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$BACKUP_DIR"
        tar -czf "$BACKUP_DIR/${APP_NAME}_backup_${TIMESTAMP}.tar.gz" -C "$PROJECT_DIR" . --exclude=node_modules --exclude=.git 2>/dev/null || warning "Backup creation had warnings"
        
        # Keep only last 5 backups
        ls -t "$BACKUP_DIR/${APP_NAME}_backup_"*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
        log "✅ Backup created: ${APP_NAME}_backup_${TIMESTAMP}.tar.gz"
    else
        info "No existing deployment to backup"
    fi
    
    # Stop the application before updating files
    log "🛑 Stopping application..."
    if command -v pm2 &> /dev/null && pm2 list | grep -q "$APP_NAME"; then
        pm2 stop "$APP_NAME" || warning "Could not stop PM2 process"
    elif systemctl is-active --quiet "$APP_NAME" 2>/dev/null; then
        sudo systemctl stop "$APP_NAME" || warning "Could not stop systemd service"
    elif [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
        (cd "$PROJECT_DIR" && docker-compose down) || warning "Could not stop docker-compose"
    fi
    
    # Copy new files to project directory
    log "📋 Copying new files to project directory..."
    rsync -av --delete --exclude='node_modules' --exclude='.env' --exclude='*.log' "$EXTRACTED_DIR/" "$PROJECT_DIR/" || {
        error "Failed to copy files"
        cleanup
        exit 1
    }
    log "✅ Files copied successfully"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Install/update dependencies
    log "📦 Installing dependencies..."
    if [ -f "package.json" ]; then
        npm ci --production || npm install --production || {
            error "Failed to install dependencies"
            cleanup
            exit 1
        }
        log "✅ Dependencies installed"
    else
        warning "No package.json found, skipping npm install"
    fi
    
    # Run build if build script exists
    if [ -f "package.json" ] && grep -q '"build"' package.json 2>/dev/null; then
        log "🔨 Building application..."
        npm run build || {
            error "Build failed"
            cleanup
            exit 1
        }
        log "✅ Build completed"
    fi
    
    # Run database migrations if script exists
    if [ -f "package.json" ] && grep -q '"migrate"' package.json 2>/dev/null; then
        log "🗄️  Running database migrations..."
        npm run migrate || warning "Migration failed"
    fi
    
    # Restart the application
    log "🔄 Starting application..."
    
    # Check if using PM2
    if command -v pm2 &> /dev/null; then
        if pm2 list | grep -q "$APP_NAME"; then
            pm2 restart "$APP_NAME"
            log "✅ Application restarted with PM2"
        else
            info "PM2 process '$APP_NAME' not found, starting new instance"
            if [ -f "ecosystem.config.js" ]; then
                pm2 start ecosystem.config.js
            else
                pm2 start index.js --name "$APP_NAME"
            fi
            pm2 save
            log "✅ Application started with PM2"
        fi
    # Check if using systemd
    elif systemctl list-units --type=service --all | grep -q "$APP_NAME.service"; then
        sudo systemctl restart "$APP_NAME"
        log "✅ Application restarted with systemd"
    # Check if using docker-compose
    elif [ -f "docker-compose.yml" ]; then
        docker-compose up -d --build
        log "✅ Application restarted with docker-compose"
    else
        warning "No process manager detected. Please start the application manually."
    fi
    
    # Health check
    log "🏥 Running health check..."
    sleep 5
    
    # Try common ports and endpoints
    HEALTH_CHECK_PASSED=false
    for PORT_NUM in 3000 8080 4000 5000; do
        if command -v curl &> /dev/null; then
            if curl -f "http://localhost:${PORT_NUM}/health" &> /dev/null || curl -f "http://localhost:${PORT_NUM}" &> /dev/null; then
                log "✅ Health check passed on port ${PORT_NUM}"
                HEALTH_CHECK_PASSED=true
                break
            fi
        fi
    done
    
    if [ "$HEALTH_CHECK_PASSED" = false ]; then
        warning "Health check could not verify application is running"
    fi
    
    # Cleanup temporary files
    cleanup
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "✨ Deployment completed successfully!"
    log "🏷️  Deployed version: $TAG_NAME"
    log "⏰ Completed at: $(date +'%Y-%m-%d %H:%M:%S')"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Error handling
trap 'error "Deployment failed at line $LINENO"; cleanup; exit 1' ERR

# Cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
