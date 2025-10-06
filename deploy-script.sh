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
VERBOSE_LOGGING=true  # Set to false to disable verbose diagnostics

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
    log "📦 Download URL: $TARBALL_URL"
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
        if [ "$VERBOSE_LOGGING" = true ] && [ "$USE_LOG_FILE" = true ]; then
            curl -L -o "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" 2>&1 | tee -a "$LOG_FILE" || {
                error "Failed to download tarball"
                cleanup
                exit 1
            }
        else
            curl -L -o "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" || {
                error "Failed to download tarball"
                cleanup
                exit 1
            }
        fi
    elif command -v wget &> /dev/null; then
        if [ "$VERBOSE_LOGGING" = true ] && [ "$USE_LOG_FILE" = true ]; then
            wget -O "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" 2>&1 | tee -a "$LOG_FILE" || {
                error "Failed to download tarball"
                cleanup
                exit 1
            }
        else
            wget -O "$TEMP_DIR/release.tar.gz" "$TARBALL_URL" || {
                error "Failed to download tarball"
                cleanup
                exit 1
            }
        fi
    else
        error "Neither curl nor wget found. Cannot download tarball."
        cleanup
        exit 1
    fi
    log "✅ Tarball downloaded"
    
    # Verify the downloaded file
    log "🔍 Verifying downloaded file..."
    
    # Check if file exists and has content
    if [ ! -f "$TEMP_DIR/release.tar.gz" ]; then
        error "Downloaded file does not exist"
        cleanup
        exit 1
    fi
    
    FILE_SIZE=$(stat -f%z "$TEMP_DIR/release.tar.gz" 2>/dev/null || stat -c%s "$TEMP_DIR/release.tar.gz" 2>/dev/null || echo "0")
    
    if [ "$VERBOSE_LOGGING" = true ]; then
        info "📊 Downloaded file size: $FILE_SIZE bytes"
    fi
    
    if [ "$FILE_SIZE" -lt 1024 ]; then
        error "Downloaded file is too small ($FILE_SIZE bytes). Likely an error page."
        if [ "$VERBOSE_LOGGING" = true ]; then
            info "First 500 bytes of file:"
            if [ "$USE_LOG_FILE" = true ]; then
                head -c 500 "$TEMP_DIR/release.tar.gz" 2>&1 | tee -a "$LOG_FILE"
            else
                head -c 500 "$TEMP_DIR/release.tar.gz" 2>&1
            fi
        fi
        cleanup
        exit 1
    fi
    
    # Check file type
    FILE_TYPE=$(file -b "$TEMP_DIR/release.tar.gz" 2>/dev/null || echo "unknown")
    
    if [ "$VERBOSE_LOGGING" = true ]; then
        info "📄 File type: $FILE_TYPE"
    fi
    
    if ! echo "$FILE_TYPE" | grep -qi "gzip\|compressed"; then
        error "Downloaded file is not a gzip archive. Got: $FILE_TYPE"
        if [ "$VERBOSE_LOGGING" = true ]; then
            info "First 500 bytes of file:"
            if [ "$USE_LOG_FILE" = true ]; then
                head -c 500 "$TEMP_DIR/release.tar.gz" 2>&1 | tee -a "$LOG_FILE"
            else
                head -c 500 "$TEMP_DIR/release.tar.gz" 2>&1
            fi
        fi
        cleanup
        exit 1
    fi
    
    # Test gzip integrity
    if command -v gzip &> /dev/null; then
        GZIP_OUTPUT=$(gzip -t "$TEMP_DIR/release.tar.gz" 2>&1)
        if [ $? -ne 0 ]; then
            error "Gzip integrity check failed. File is corrupted."
            error "$GZIP_OUTPUT"
            cleanup
            exit 1
        fi
        log "✅ Gzip integrity verified"
    fi
    
    log "✅ File verification passed"
    
    # Extract tarball
    log "📦 Extracting tarball..."
    mkdir "$TEMP_DIR/extracted"
    
    # Capture tar output for debugging
    if [ "$VERBOSE_LOGGING" = true ]; then
        TAR_OUTPUT=$(tar -xvf "$TEMP_DIR/release.tar.gz" -C "$TEMP_DIR/extracted" 2>&1)
        TAR_EXIT_CODE=$?
    else
        tar -xf "$TEMP_DIR/release.tar.gz" -C "$TEMP_DIR/extracted" 2>&1
        TAR_EXIT_CODE=$?
    fi
    
    if [ $TAR_EXIT_CODE -ne 0 ]; then
        error "Failed to extract tarball (exit code: $TAR_EXIT_CODE)"
        
        if [ "$VERBOSE_LOGGING" = true ]; then
            error "Tar command output:"
            if [ "$USE_LOG_FILE" = true ]; then
                echo "$TAR_OUTPUT" | tee -a "$LOG_FILE"
            else
                echo "$TAR_OUTPUT"
            fi
            
            # Additional diagnostics
            info "Attempting to list tarball contents..."
            if [ "$USE_LOG_FILE" = true ]; then
                tar -tzf "$TEMP_DIR/release.tar.gz" 2>&1 | head -20 | tee -a "$LOG_FILE" || error "Cannot list tarball contents"
            else
                tar -tzf "$TEMP_DIR/release.tar.gz" 2>&1 | head -20 || error "Cannot list tarball contents"
            fi
        fi
        
        cleanup
        exit 1
    fi
    
    # Log extraction details
    if [ "$VERBOSE_LOGGING" = true ]; then
        info "Tar extraction output (first 20 lines):"
        if [ "$USE_LOG_FILE" = true ]; then
            echo "$TAR_OUTPUT" | head -20 | tee -a "$LOG_FILE"
        else
            echo "$TAR_OUTPUT" | head -20
        fi
    fi
    
    EXTRACTED_DIR="$TEMP_DIR/extracted"
    
    if [ -z "$EXTRACTED_DIR" ]; then
        error "Could not find extracted directory"
        cleanup
        exit 1
    fi
    
    log "✅ Tarball extracted to: $EXTRACTED_DIR"
    
    # Show what's in the extracted directory
    info "📂 Contents of extracted directory:"
    ls -la "$EXTRACTED_DIR" | tail -n +4 | while read line; do
        info "   $line"
    done
    
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
        tar -czf "$BACKUP_DIR/${APP_NAME}_backup_${TIMESTAMP}.tar.gz" -C "$PROJECT_DIR" . 2>/dev/null || warning "Backup creation had warnings"
        
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
    
    # Delete everything in project directory
    log "🗑️  Clearing project directory..."
    rm -rf "$PROJECT_DIR"/*
    rm -rf "$PROJECT_DIR"/.[!.]*  # Delete hidden files but not . and ..
    log "✅ Project directory cleared"
    
    # Copy all files from extracted directory
    log "📋 Copying new files to project directory..."
    cp -r "$EXTRACTED_DIR"/* "$PROJECT_DIR/" || {
        error "Failed to copy files"
        cleanup
        exit 1
    }
    
    # Also copy hidden files if they exist
    if ls "$EXTRACTED_DIR"/.[!.]* 1> /dev/null 2>&1; then
        cp -r "$EXTRACTED_DIR"/.[!.]* "$PROJECT_DIR/" 2>/dev/null || true
    fi
    log "✅ Files copied successfully"
    
    # Show what's now in the project directory
    info "📂 Contents of project directory after deployment:"
    ls -la "$PROJECT_DIR" | tail -n +4 | while read line; do
        info "   $line"
    done
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Install/update dependencies
    log "📦 Installing dependencies..."
    if [ -f "package.json" ]; then
        npm ci --omit=dev || npm install --omit=dev || {
            error "Failed to install dependencies"
            cleanup
            exit 1
        }
        log "✅ Dependencies installed"
    else
        warning "No package.json found, skipping npm install"
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
