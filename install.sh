#!/bin/bash
#
# One-Command Scanner CLI Installer
# Downloads only the scanner_master_cli folder and sets it up
#
# Usage (one-liner):
#   curl -fsSL https://raw.githubusercontent.com/morphiens/scanner-cli-installer/main/install.sh | bash
#   OR (if already in directory):
#   bash install.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SOURCE_REPO="git@github.com:morphiens/scano.git"
SOURCE_REPO_BRANCH="feat/cli-setup-v5.2"
SOURCE_SUBDIR="scripts/scanner_master_cli"

# Detect actual user (not root if sudo was used)
ACTUAL_USER="${SUDO_USER:-${USER}}"
ACTUAL_HOME=$(eval echo "~$ACTUAL_USER")

# Determine download directory: /etc/morphle/code/ if available, else ~/Downloads
if [ -d "/etc/morphle/code" ] && [ -w "/etc/morphle/code" ]; then
    DOWNLOAD_DIR="/etc/morphle/code/scanner_master_cli"
else
    DOWNLOAD_DIR="$ACTUAL_HOME/Downloads/scanner_master_cli"
fi

echo ""
echo "========================================"
echo "  Scanner CLI One-Command Installer"
echo "========================================"
echo ""
echo "Download directory: $DOWNLOAD_DIR"
echo ""

# Warn if running as root
if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "${YELLOW}⚠ Warning: Running as root. SSH keys will be created in /root/.ssh${NC}"
    echo -e "${YELLOW}  Consider running without sudo for user-level installation${NC}"
    echo ""
fi

# Check for git
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git not found. Please install git first.${NC}" && exit 1
fi

# Check storage availability before cloning
echo "Checking storage availability..."
DOWNLOAD_PARENT_DIR=$(dirname "$DOWNLOAD_DIR")
if [ ! -d "$DOWNLOAD_PARENT_DIR" ]; then
    echo "Creating parent directory: $DOWNLOAD_PARENT_DIR"
    mkdir -p "$DOWNLOAD_PARENT_DIR" || {
        echo -e "${RED}Error: Failed to create parent directory: $DOWNLOAD_PARENT_DIR${NC}" && exit 1
    }
fi

if [ ! -w "$DOWNLOAD_PARENT_DIR" ]; then
    echo -e "${RED}Error: Storage location is not writable: $DOWNLOAD_PARENT_DIR${NC}" && exit 1
fi
echo -e "${GREEN}✓${NC} Storage location is available: $DOWNLOAD_PARENT_DIR"
echo ""

# Function to check SSH auth silently (using actual user's home)
check_ssh_auth_silent() {
    local ssh_dir="$ACTUAL_HOME/.ssh"
    local ssh_test_cmd
    local ssh_output
    
    # Check for existing SSH keys
    if [ ! -f "$ssh_dir/id_rsa" ] && [ ! -f "$ssh_dir/id_ed25519" ]; then
        return 1
    fi
    
    # Test GitHub connection silently
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        ssh_test_cmd="sudo -u $SUDO_USER ssh"
    else
        ssh_test_cmd="ssh"
    fi
    
    # Test SSH connection - GitHub responds with "Hi username!" on success
    # Exit code 1 means authentication failed, exit code 255 means connection error
    ssh_output=$($ssh_test_cmd -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -T git@github.com 2>&1)
    local exit_code=$?
    
    # Check for successful authentication (GitHub responds with "Hi" message)
    if echo "$ssh_output" | grep -qiE "(hi |successfully authenticated|you've successfully authenticated)"; then
        return 0
    fi
    
    # Also check exit code - if it's 1, it might be auth failure, but if it's 255, it's connection issue
    # Exit code 1 with "Permission denied" means auth failed
    if [ $exit_code -eq 1 ] && echo "$ssh_output" | grep -qi "permission denied"; then
        return 1
    fi
    
    # If we got here, assume failure
    return 1
}

# Function to set up SSH auth
setup_ssh_auth() {
    local ssh_dir="$ACTUAL_HOME/.ssh"
    local key_file=""
    local key_type=""
    
    echo "Setting up SSH authentication..."
    
    # Check if keys exist, if not generate one
    if [ ! -f "$ssh_dir/id_ed25519" ] && [ ! -f "$ssh_dir/id_rsa" ]; then
        echo "Generating SSH key..."
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        
        # Generate key as actual user if possible
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "scanner-cli-installer" || {
                echo -e "${RED}Error: Failed to generate SSH key${NC}" && exit 1
            }
            sudo -u "$SUDO_USER" chmod 600 "$ssh_dir/id_ed25519" 2>/dev/null || true
            sudo -u "$SUDO_USER" chmod 644 "$ssh_dir/id_ed25519.pub" 2>/dev/null || true
        else
            ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "scanner-cli-installer" || {
                echo -e "${RED}Error: Failed to generate SSH key${NC}" && exit 1
            }
            chmod 600 "$ssh_dir/id_ed25519" 2>/dev/null || true
            chmod 644 "$ssh_dir/id_ed25519.pub" 2>/dev/null || true
        fi
        
        echo -e "${GREEN}✓${NC} SSH key generated"
    fi
    
    # Determine which key to use
    if [ -f "$ssh_dir/id_ed25519" ]; then
        key_file="$ssh_dir/id_ed25519"
        key_type="ed25519"
    elif [ -f "$ssh_dir/id_rsa" ]; then
        key_file="$ssh_dir/id_rsa"
        key_type="rsa"
    fi
    
    # Ensure proper permissions on existing keys
    if [ -n "$key_file" ]; then
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$SUDO_USER" chmod 600 "$key_file" 2>/dev/null || true
            sudo -u "$SUDO_USER" chmod 644 "${key_file}.pub" 2>/dev/null || true
        else
            chmod 600 "$key_file" 2>/dev/null || true
            chmod 644 "${key_file}.pub" 2>/dev/null || true
        fi
    fi
    
    # Show public key
    echo ""
    echo "Public key to add to GitHub:"
    echo "----------------------------------------"
    if [ -f "$ssh_dir/id_ed25519.pub" ]; then
        cat "$ssh_dir/id_ed25519.pub"
    elif [ -f "$ssh_dir/id_rsa.pub" ]; then
        cat "$ssh_dir/id_rsa.pub"
    fi
    echo "----------------------------------------"
    echo ""
    echo "Add it at: https://github.com/settings/keys"
    echo ""
    read -p "Press Enter after adding the key to GitHub..."
    
    # Try to add key to ssh-agent if available
    if command -v ssh-add &> /dev/null; then
        echo "Adding key to ssh-agent..."
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$SUDO_USER" ssh-add "$key_file" 2>/dev/null || true
        else
            ssh-add "$key_file" 2>/dev/null || true
        fi
    fi
    
    # Wait a moment for GitHub to propagate the key
    echo "Waiting a few seconds for GitHub to recognize the key..."
    sleep 3
}

# Check SSH authentication before cloning
echo "Checking SSH authentication..."
export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

if ! check_ssh_auth_silent; then
    echo -e "${YELLOW}⚠${NC} SSH authentication not available"
    if [ -t 0 ] && [ -t 1 ]; then
        echo ""
        read -p "Do you want to set up SSH authentication? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_ssh_auth
            # Verify SSH auth after setup with retries
            echo "Verifying SSH authentication..."
            local retry_count=0
            local max_retries=3
            while [ $retry_count -lt $max_retries ]; do
                if check_ssh_auth_silent; then
                    echo -e "${GREEN}✓${NC} SSH authentication verified"
                    break
                else
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -lt $max_retries ]; then
                        echo -e "${YELLOW}⚠${NC} SSH authentication not yet working (attempt $retry_count/$max_retries)${NC}"
                        echo -e "${YELLOW}  Waiting 2 seconds before retry...${NC}"
                        sleep 2
                    else
                        echo -e "${YELLOW}⚠${NC} SSH authentication still not working after $max_retries attempts.${NC}"
                        echo -e "${YELLOW}  Please verify:${NC}"
                        echo -e "${YELLOW}  1. The key was added to GitHub at https://github.com/settings/keys${NC}"
                        echo -e "${YELLOW}  2. You clicked 'Add SSH key' button${NC}"
                        echo -e "${YELLOW}  3. The key matches the one shown above${NC}"
                        echo -e "${YELLOW}  Continuing anyway - clone will fail if authentication is not working...${NC}"
                    fi
                fi
            done
        else
            echo -e "${RED}Error: SSH authentication required. Cannot proceed without repository access.${NC}" && exit 1
        fi
    else
        echo -e "${RED}Error: SSH authentication required. Cannot proceed without repository access.${NC}" && exit 1
    fi
else
    echo -e "${GREEN}✓${NC} SSH authentication available"
fi

# Clone repository via SSH only
echo "Cloning repository via SSH..."
TEMP_CLONE_DIR=$(mktemp -d)
trap "rm -rf $TEMP_CLONE_DIR" EXIT

if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$SOURCE_REPO_BRANCH" "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1; then
    echo -e "${RED}Error: Failed to clone repository${NC}"
    echo -e "${RED}  Branch '$SOURCE_REPO_BRANCH' may not exist or SSH authentication failed${NC}" && exit 1
fi

# Check if source directory exists
SOURCE_PATH="$TEMP_CLONE_DIR/$SOURCE_SUBDIR"
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${RED}Error: Source directory '$SOURCE_SUBDIR' not found in repository${NC}" && exit 1
fi

# Create download directory and copy files
mkdir -p "$DOWNLOAD_DIR"
FILES=("setup_scanner_cli.sh" "interactive_maneuver.py" "log_collector.py" "drive_uploader.py" "requirements.txt")

for file in "${FILES[@]}"; do
    if [ ! -f "$SOURCE_PATH/$file" ]; then
        echo -e "${RED}Error: $file not found in repository${NC}" && exit 1
    fi
    cp "$SOURCE_PATH/$file" "$DOWNLOAD_DIR/$file"
    chmod +x "$DOWNLOAD_DIR/$file" 2>/dev/null || true
done

# Clean up temp clone
rm -rf "$TEMP_CLONE_DIR"
trap - EXIT

INSTALL_DIR="$(cd "$DOWNLOAD_DIR" && pwd)"
echo -e "${GREEN}✓${NC} Files downloaded successfully to: $INSTALL_DIR"
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
