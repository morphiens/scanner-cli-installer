#!/bin/bash
#
# One-Command Scanner CLI Installer
# Downloads only the scanner_master_cli folder and sets it up
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/morphiens/scanner-cli-installer/main/install.sh | sudo bash
#   OR (if already in directory):
#   sudo bash install.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SOURCE_REPO="git@github.com:morphiens/scano.git"
SOURCE_REPO_BRANCH="feat/cli-setup-v5.2"
SOURCE_SUBDIR="scripts/scanner_master_cli"
DOWNLOAD_DIR="scanner_master_cli"

echo ""
echo "========================================"
echo "  Scanner CLI One-Command Installer"
echo "========================================"
echo ""

# Check for git
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found${NC}" && exit 1
fi

# Function to check and initialize SSH auth
check_ssh_auth() {
    local ssh_key_found=false
    local ssh_dir="$HOME/.ssh"
    
    # Check for existing SSH keys
    if [ -f "$ssh_dir/id_rsa" ] || [ -f "$ssh_dir/id_ed25519" ]; then
        ssh_key_found=true
    fi
    
    # If no keys found, generate one
    if [ "$ssh_key_found" = false ]; then
        echo "No SSH keys found. Generating SSH key..."
        mkdir -p "$ssh_dir"
        ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "scanner-cli-installer" || {
            echo -e "${RED}Error: Failed to generate SSH key${NC}" && exit 1
        }
        echo -e "${GREEN}✓${NC} SSH key generated"
    fi
    
    # Test GitHub connection
    echo "Testing SSH connection to GitHub..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo -e "${GREEN}✓${NC} SSH authentication verified"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} SSH key not added to GitHub. Please add the public key:"
        if [ -f "$ssh_dir/id_ed25519.pub" ]; then
            echo "  cat $ssh_dir/id_ed25519.pub"
            cat "$ssh_dir/id_ed25519.pub"
        elif [ -f "$ssh_dir/id_rsa.pub" ]; then
            echo "  cat $ssh_dir/id_rsa.pub"
            cat "$ssh_dir/id_rsa.pub"
        fi
        echo ""
        echo "Add it at: https://github.com/settings/keys"
        echo -e "${RED}Error: SSH authentication failed${NC}" && exit 1
    fi
}

# Check SSH auth
check_ssh_auth

# Clone repository
echo "Cloning repository..."
TEMP_CLONE_DIR=$(mktemp -d)
trap "rm -rf $TEMP_CLONE_DIR" EXIT

export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"
if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$SOURCE_REPO_BRANCH" "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1; then
    echo -e "${YELLOW}⚠${NC} Branch '$SOURCE_REPO_BRANCH' not found, trying main branch..."
    rm -rf "$TEMP_CLONE_DIR"
    TEMP_CLONE_DIR=$(mktemp -d)
    if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1; then
        echo -e "${RED}Error: Failed to clone repository${NC}" && exit 1
    fi
fi

# Check if source directory exists
SOURCE_PATH="$TEMP_CLONE_DIR/$SOURCE_SUBDIR"
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${RED}Error: Source directory not found${NC}" && exit 1
fi

# Create download directory and copy files
mkdir -p "$DOWNLOAD_DIR"
FILES=("setup_scanner_cli.sh" "interactive_maneuver.py" "log_collector.py" "drive_uploader.py" "requirements.txt")

for file in "${FILES[@]}"; do
    if [ ! -f "$SOURCE_PATH/$file" ]; then
        echo -e "${RED}Error: $file not found in repository${NC}" && exit 1
    fi
    cp "$SOURCE_PATH/$file" "$DOWNLOAD_DIR/$file"
done

# Clean up temp clone
rm -rf "$TEMP_CLONE_DIR"
trap - EXIT

INSTALL_DIR="$(cd "$DOWNLOAD_DIR" && pwd)"
echo -e "${GREEN}✓${NC} Files downloaded successfully"
echo ""

# Validate installation directory
if [ ! -f "$INSTALL_DIR/setup_scanner_cli.sh" ]; then
    echo -e "${RED}Error: setup_scanner_cli.sh not found${NC}" && exit 1
fi

# Check for sudo and run setup script
if [ "$EUID" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        sudo bash "$INSTALL_DIR/setup_scanner_cli.sh" "$INSTALL_DIR"
        EXIT_CODE=$?
    elif [ -t 0 ] && [ -t 1 ]; then
        sudo bash "$INSTALL_DIR/setup_scanner_cli.sh" "$INSTALL_DIR"
        EXIT_CODE=$?
    else
        echo -e "${RED}Error: Non-interactive mode and sudo requires password${NC}" && exit 1
    fi
else
    bash "$INSTALL_DIR/setup_scanner_cli.sh" "$INSTALL_DIR"
    EXIT_CODE=$?
fi

exit $EXIT_CODE
