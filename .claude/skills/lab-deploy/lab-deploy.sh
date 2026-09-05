#!/bin/bash
# Lab deployment + log harvest pipeline
# Usage: lab-deploy [build-path] [deploy-to-lab] [harvest-logs]

set -e

LAB_HOST="192.168.1.143"
LAB_USER="trondheim golfsenter"
LAB_PASS="${LAB_DEPLOY_PASSWORD:-swingers}"  # Set via env or prompt
DEPLOY_DIR="C:\\Program Files\\Initial Force\\Swing Catalyst Alpha"
LOG_SOURCE="C:\\ProgramData\\Swing Catalyst\\logs"
DESKTOP_SHORTCUT="C:\\Users\\${LAB_USER}\\Desktop\\Swing Catalyst Alpha.lnk"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# Step 1: Build Release binary (if build-path provided)
if [[ "$1" == "build" || -n "$1" ]]; then
    BUILD_PATH="${1:-.}"
    log_info "Building Release binary from $BUILD_PATH..."

    if [[ -f "$BUILD_PATH/build.cmd" ]]; then
        cd "$BUILD_PATH"
        timeout 600 cmd.exe /c "build.cmd build -c Release" || log_error "Build failed"
        log_success "Release build complete"
    else
        log_error "build.cmd not found at $BUILD_PATH"
    fi
fi

# Step 2: Deploy to lab machine
deploy_to_lab() {
    log_info "Deploying to lab machine ($LAB_HOST)..."

    # Create deploy directory
    timeout 30 bash -c "sshpass -p '$LAB_PASS' ssh -o StrictHostKeyChecking=accept-new '$LAB_USER@$LAB_HOST' \"mkdir -p '$DEPLOY_DIR'\"" || \
        log_error "Failed to create deploy directory"

    # Copy Release binary (assumes src/motioncatalyst/BUILD/x64_Release/MotionCatalyst.exe exists)
    if [[ -f "src/motioncatalyst/BUILD/x64_Release/MotionCatalyst.exe" ]]; then
        log_info "Copying MotionCatalyst.exe..."
        timeout 120 bash -c "sshpass -p '$LAB_PASS' ssh -o StrictHostKeyChecking=accept-new '$LAB_USER@$LAB_HOST' \"type src\\motioncatalyst\\BUILD\\x64_Release\\MotionCatalyst.exe > '$DEPLOY_DIR\\MotionCatalyst.exe'\"" || \
            log_error "Failed to deploy binary"
        log_success "Binary deployed"
    else
        log_error "Release binary not found at src/motioncatalyst/BUILD/x64_Release/MotionCatalyst.exe"
    fi

    # Create desktop shortcut (PowerShell script)
    log_info "Creating desktop shortcut..."
    SHORTCUT_SCRIPT='$WshShell = New-Object -ComObject WScript.Shell; $shortcut = $WshShell.CreateShortcut('"'$DESKTOP_SHORTCUT'"'); $shortcut.TargetPath = '"'"'"'"'"'"'$DEPLOY_DIR\\MotionCatalyst.exe'"'"'"'"'"'"'; $shortcut.Save()'

    timeout 30 bash -c "sshpass -p '$LAB_PASS' ssh -o StrictHostKeyChecking=accept-new '$LAB_USER@$LAB_HOST' \"powershell -NoProfile -Command \\\"$SHORTCUT_SCRIPT\\\"\"" || \
        log_error "Failed to create shortcut"

    log_success "Desktop shortcut created"
}

# Step 3: Harvest logs from lab
harvest_logs() {
    log_info "Harvesting logs from lab machine..."

    HARVEST_DIR="$HOME/.lab-logs/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$HARVEST_DIR"

    # Download latest log files
    for logfile in log.1.txt log.20260623.txt log.20260622.txt; do
        log_info "Downloading $logfile..."
        timeout 120 bash -c "sshpass -p '$LAB_PASS' ssh -o StrictHostKeyChecking=accept-new '$LAB_USER@$LAB_HOST' \"type \\\"$LOG_SOURCE\\\\$logfile\\\"\" > \"$HARVEST_DIR/$logfile\" 2>&1" && \
            log_success "Downloaded $logfile" || true
    done

    # Analyze for errors
    log_info "Scanning for errors..."
    ERROR_COUNT=$(grep -c "ERROR\|FATAL" "$HARVEST_DIR"/*.txt 2>/dev/null || echo 0)
    log_info "Found $ERROR_COUNT error/fatal entries"

    # Create summary
    cat > "$HARVEST_DIR/HARVEST_SUMMARY.txt" <<EOF
Lab Harvest: $(date)
Host: $LAB_HOST
User: $LAB_USER
Deploy Dir: $DEPLOY_DIR
Logs harvested: $(ls -1 "$HARVEST_DIR"/*.txt 2>/dev/null | wc -l) files
Error/Fatal count: $ERROR_COUNT
EOF

    log_success "Logs harvested to $HARVEST_DIR"
    echo "Summary:" && cat "$HARVEST_DIR/HARVEST_SUMMARY.txt"
}

# Main
case "$2" in
    "deploy")
        deploy_to_lab
        ;;
    "harvest")
        harvest_logs
        ;;
    *)
        log_info "Lab deployment + harvest pipeline"
        log_info "Usage: lab-deploy [build|path] [deploy|harvest]"
        echo ""
        echo "Examples:"
        echo "  lab-deploy build deploy          # Build + deploy Release binary"
        echo "  lab-deploy . deploy              # Deploy existing Release binary"
        echo "  lab-deploy . harvest             # Harvest logs from lab"
        echo "  lab-deploy build deploy harvest  # Build, deploy, then harvest"
        ;;
esac
