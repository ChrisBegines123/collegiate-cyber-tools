#!/bin/bash
#=============================================================================
# CCDC26 Standalone Deployment Script
#=============================================================================
# Deploys the toolkit directly on this machine without requiring Ansible
# Useful when Ansible connectivity fails or for manual deployment
#
# Usage:
#   sudo ./deploy-standalone.sh
#   sudo ./deploy-standalone.sh --repo-url https://github.com/byui-soc/ccdc26.git
#   sudo ./deploy-standalone.sh --run-hardening
#=============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_DEST="/opt/ccdc26"
REPO_URL="${REPO_URL:-https://github.com/byui-soc/ccdc26.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
RUN_HARDENING=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}${PURPLE}=== $1 ===${NC}\n"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --repo-url)
            REPO_URL="$2"
            shift 2
            ;;
        --branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        --run-hardening)
            RUN_HARDENING=true
            shift
            ;;
        --help|-h)
            echo "CCDC26 Standalone Deployment"
            echo ""
            echo "Usage: sudo $0 [options]"
            echo ""
            echo "Options:"
            echo "  --repo-url URL    Repository URL (default: from env or github)"
            echo "  --branch BRANCH   Branch to clone (default: main)"
            echo "  --run-hardening   Run hardening scripts after deployment"
            echo "  --help            Show this help"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if root
if [ "$EUID" -ne 0 ]; then
    error "Must be root. Run: sudo $0"
    exit 1
fi

header "CCDC26 Standalone Deployment"

# Check for git
if ! command -v git &>/dev/null; then
    info "Git not found, installing..."
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y git
    elif command -v yum &>/dev/null; then
        yum install -y git
    elif command -v dnf &>/dev/null; then
        dnf install -y git
    else
        error "Cannot install git automatically. Please install git first."
        exit 1
    fi
fi

# Clone or update repository
info "Deploying toolkit to $TOOLKIT_DEST"
info "Repository: $REPO_URL"
info "Branch: $REPO_BRANCH"

if [ -d "$TOOLKIT_DEST/.git" ]; then
    info "Repository exists, updating..."
    cd "$TOOLKIT_DEST"
    git fetch origin
    git checkout "$REPO_BRANCH"
    git pull origin "$REPO_BRANCH"
    success "Repository updated"
else
    info "Cloning repository..."
    if [ -d "$TOOLKIT_DEST" ]; then
        warn "Directory $TOOLKIT_DEST exists but is not a git repo. Backing up..."
        mv "$TOOLKIT_DEST" "${TOOLKIT_DEST}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TOOLKIT_DEST"
    success "Repository cloned"
fi

# Make scripts executable
info "Setting script permissions..."
find "$TOOLKIT_DEST/linux-scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
success "Scripts are executable"

# Display toolkit location
echo ""
success "Toolkit deployed to: $TOOLKIT_DEST"
echo ""
info "Available commands:"
echo "  cd $TOOLKIT_DEST/linux-scripts"
echo "  sudo ./hardening/full-harden.sh          # Run full hardening"
echo "  sudo ./services/harden-all.sh             # Harden all services"
echo "  sudo ./tools/splunk-forwarder.sh         # Install Splunk forwarder"
echo "  sudo ./persistence-hunting/full-hunt.sh  # Hunt for persistence"
echo ""

# Run hardening if requested
if [ "$RUN_HARDENING" = true ]; then
    header "Running Full Hardening"
    cd "$TOOLKIT_DEST/linux-scripts"
    if [ -f "./hardening/full-harden.sh" ]; then
        bash ./hardening/full-harden.sh
        success "Hardening complete"
    else
        error "Hardening script not found"
        exit 1
    fi
fi

success "Deployment complete!"
