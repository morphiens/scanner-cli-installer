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

SOURCE_REPO_SSH="git@github.com:morphiens/scano.git"
SOURCE_REPO_HTTPS="https://github.com/morphiens/scano.git"
SOURCE_REPO_BRANCH="feat/cli-setup-v5.2"
SOURCE_SUBDIR="scripts/scanner_master_cli"

# Detect actual user (not root if sudo was used)
ACTUAL_USER="${SUDO_USER:-${USER}}"
ACTUAL_HOME=$(eval echo "~$ACTUAL_USER")

# Determine download directory: /media/scandrive if available, else ~/Downloads
# Check permissions and detect if sudo is needed
NEED_SUDO_FOR_DIR=false
if [ -d "/media/scandrive" ]; then
    DOWNLOAD_DIR="/media/scandrive/scanner_master_cli"
    # Check if we can write to parent directory
    if [ ! -w "/media/scandrive" ]; then
        # Parent directory exists but not writable - will need sudo
        NEED_SUDO_FOR_DIR=true
    else
        # Parent is writable, but check if subdirectory creation works
        # Test by trying to create it (will clean up if successful)
        mkdir -p "/media/scandrive/scanner_master_cli" 2>/dev/null && {
            # Created successfully, remove test directory
            rmdir "/media/scandrive/scanner_master_cli" 2>/dev/null || true
        } || {
            # Failed to create - will need sudo
            NEED_SUDO_FOR_DIR=true
        }
    fi
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

# Function to check SSH auth silently (using actual user's home)
check_ssh_auth_silent() {
    local ssh_dir="$ACTUAL_HOME/.ssh"
    local ssh_test_cmd
    
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
    
    if $ssh_test_cmd -o ConnectTimeout=5 -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        return 0
    else
        return 1
    fi
}

# Function to set up SSH auth
setup_ssh_auth() {
    local ssh_dir="$ACTUAL_HOME/.ssh"
    
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
        else
            ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "scanner-cli-installer" || {
                echo -e "${RED}Error: Failed to generate SSH key${NC}" && exit 1
            }
        fi
        
        echo -e "${GREEN}✓${NC} SSH key generated"
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
}

# Try SSH first silently
USE_SSH=false
SOURCE_REPO="$SOURCE_REPO_HTTPS"
unset GIT_SSH_COMMAND

if check_ssh_auth_silent; then
    USE_SSH=true
    SOURCE_REPO="$SOURCE_REPO_SSH"
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
    echo -e "${GREEN}✓${NC} Using SSH authentication"
else
    echo -e "${BLUE}→${NC} Trying HTTPS authentication"
fi

# Clone repository
echo "Cloning repository..."
TEMP_CLONE_DIR=$(mktemp -d)
trap "rm -rf $TEMP_CLONE_DIR" EXIT

CLONE_SUCCESS=false
GIT_ERROR_OUTPUT=""
AUTH_METHOD="HTTPS"
if [ "$USE_SSH" = true ]; then
    AUTH_METHOD="SSH"
fi

# Try cloning with specified branch
GIT_ERROR_OUTPUT=$(GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$SOURCE_REPO_BRANCH" "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1) && {
    CLONE_SUCCESS=true
} || {
    # Clone failed, capture error
    echo -e "${YELLOW}⚠${NC} Failed to clone branch '$SOURCE_REPO_BRANCH' using $AUTH_METHOD authentication"
    echo -e "${YELLOW}Error details:${NC}"
    echo "$GIT_ERROR_OUTPUT" | sed 's/^/  /'
    echo ""
    
    # Try main branch
    echo -e "${YELLOW}⚠${NC} Trying main branch..."
    rm -rf "$TEMP_CLONE_DIR"
    TEMP_CLONE_DIR=$(mktemp -d)
    GIT_ERROR_OUTPUT=$(GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1) && {
        CLONE_SUCCESS=true
    } || {
        # Main branch also failed
        CLONE_SUCCESS=false
    }
}

# If both methods failed, ask about SSH setup
if [ "$CLONE_SUCCESS" = false ]; then
    echo -e "${RED}Error: Failed to clone repository using $AUTH_METHOD authentication${NC}"
    if [ -n "$GIT_ERROR_OUTPUT" ]; then
        echo -e "${RED}Git error output:${NC}"
        echo "$GIT_ERROR_OUTPUT" | sed 's/^/  /'
        echo ""
    fi
    
    # If we tried HTTPS and it failed, and SSH wasn't tried or also failed
    if [ "$USE_SSH" = false ] || ! check_ssh_auth_silent; then
        if [ -t 0 ] && [ -t 1 ]; then
            echo ""
            read -p "Do you want to set up SSH authentication? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_ssh_auth
                # Retry with SSH
                USE_SSH=true
                SOURCE_REPO="$SOURCE_REPO_SSH"
                export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
                echo "Retrying clone with SSH..."
                rm -rf "$TEMP_CLONE_DIR"
                TEMP_CLONE_DIR=$(mktemp -d)
                
                GIT_ERROR_OUTPUT=$(GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$SOURCE_REPO_BRANCH" "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1) && {
                    CLONE_SUCCESS=true
                } || {
                    echo -e "${RED}Failed to clone branch '$SOURCE_REPO_BRANCH' with SSH${NC}"
                    echo -e "${RED}Error details:${NC}"
                    echo "$GIT_ERROR_OUTPUT" | sed 's/^/  /'
                    echo ""
                    echo -e "${YELLOW}Trying main branch with SSH...${NC}"
                    rm -rf "$TEMP_CLONE_DIR"
                    TEMP_CLONE_DIR=$(mktemp -d)
                    GIT_ERROR_OUTPUT=$(GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main "$SOURCE_REPO" "$TEMP_CLONE_DIR" 2>&1) && {
                        CLONE_SUCCESS=true
                    } || {
                        echo -e "${RED}Error: Failed to clone repository with SSH authentication${NC}"
                        echo -e "${RED}Error details:${NC}"
                        echo "$GIT_ERROR_OUTPUT" | sed 's/^/  /'
                        echo ""
                        echo -e "${RED}Cannot proceed without repository access${NC}"
                        exit 1
                    }
                }
            else
                echo -e "${RED}Error: Cannot proceed without repository access${NC}"
                echo -e "${YELLOW}Possible solutions:${NC}"
                echo "  1. Set up SSH authentication and retry"
                echo "  2. Ensure you have access to the repository"
                echo "  3. Check your network connection"
                exit 1
            fi
        else
            echo -e "${RED}Error: Cannot proceed without repository access${NC}"
            echo -e "${YELLOW}Non-interactive mode: Cannot set up SSH authentication${NC}"
            echo -e "${YELLOW}Possible solutions:${NC}"
            echo "  1. Run interactively to set up SSH authentication"
            echo "  2. Ensure HTTPS access is available"
            echo "  3. Check your network connection"
            exit 1
        fi
    else
        echo -e "${RED}Error: SSH authentication was attempted but failed${NC}"
        exit 1
    fi
fi

# Check if source directory exists
SOURCE_PATH="$TEMP_CLONE_DIR/$SOURCE_SUBDIR"
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${RED}Error: Source directory '$SOURCE_SUBDIR' not found in repository${NC}"
    echo -e "${YELLOW}Expected location: $SOURCE_PATH${NC}"
    echo -e "${YELLOW}Repository was cloned to: $TEMP_CLONE_DIR${NC}"
    echo -e "${YELLOW}Please verify the repository structure and branch${NC}"
    exit 1
fi

# Create download directory and copy files
echo "Creating download directory: $DOWNLOAD_DIR"
if [ "$NEED_SUDO_FOR_DIR" = true ]; then
    if sudo -n true 2>/dev/null || [ -t 0 ]; then
        sudo mkdir -p "$DOWNLOAD_DIR" || {
            echo -e "${RED}Error: Failed to create directory $DOWNLOAD_DIR${NC}"
            echo -e "${YELLOW}Permission denied. Trying without sudo...${NC}"
            NEED_SUDO_FOR_DIR=false
            # Fallback to user directory
            DOWNLOAD_DIR="$ACTUAL_HOME/Downloads/scanner_master_cli"
            mkdir -p "$DOWNLOAD_DIR" || {
                echo -e "${RED}Error: Failed to create directory $DOWNLOAD_DIR${NC}"
                echo -e "${YELLOW}Please check directory permissions or run with appropriate privileges${NC}"
                exit 1
            }
        }
    else
        echo -e "${RED}Error: Directory $DOWNLOAD_DIR requires sudo but non-interactive mode${NC}"
        echo -e "${YELLOW}Falling back to user directory...${NC}"
        DOWNLOAD_DIR="$ACTUAL_HOME/Downloads/scanner_master_cli"
        mkdir -p "$DOWNLOAD_DIR" || {
            echo -e "${RED}Error: Failed to create directory $DOWNLOAD_DIR${NC}"
            exit 1
        }
    fi
else
    mkdir -p "$DOWNLOAD_DIR" || {
        echo -e "${RED}Error: Failed to create directory $DOWNLOAD_DIR${NC}"
        echo -e "${YELLOW}Please check directory permissions${NC}"
        exit 1
    }
fi

FILES=("setup_scanner_cli.sh" "interactive_maneuver.py" "log_collector.py" "drive_uploader.py" "requirements.txt")

for file in "${FILES[@]}"; do
    if [ ! -f "$SOURCE_PATH/$file" ]; then
        echo -e "${RED}Error: $file not found in repository${NC}"
        echo -e "${YELLOW}Expected location: $SOURCE_PATH/$file${NC}"
        exit 1
    fi
    
    # Copy file with appropriate permissions
    if [ "$NEED_SUDO_FOR_DIR" = true ]; then
        sudo cp "$SOURCE_PATH/$file" "$DOWNLOAD_DIR/$file" || {
            echo -e "${RED}Error: Failed to copy $file to $DOWNLOAD_DIR${NC}"
            echo -e "${YELLOW}Permission denied. Check directory permissions${NC}"
            exit 1
        }
        sudo chmod +x "$DOWNLOAD_DIR/$file" 2>/dev/null || true
    else
        cp "$SOURCE_PATH/$file" "$DOWNLOAD_DIR/$file" || {
            echo -e "${RED}Error: Failed to copy $file to $DOWNLOAD_DIR${NC}"
            echo -e "${YELLOW}Permission denied. You may need to run with sudo${NC}"
            exit 1
        }
        chmod +x "$DOWNLOAD_DIR/$file" 2>/dev/null || true
    fi
done

# Clean up temp clone
rm -rf "$TEMP_CLONE_DIR"
trap - EXIT

INSTALL_DIR="$(cd "$DOWNLOAD_DIR" && pwd)"
echo -e "${GREEN}✓${NC} Files downloaded successfully to: $INSTALL_DIR"
echo ""

# Validate installation directory
if [ ! -f "$INSTALL_DIR/setup_scanner_cli.sh" ]; then
    echo -e "${RED}Error: setup_scanner_cli.sh not found in installation directory${NC}"
    echo -e "${YELLOW}Expected location: $INSTALL_DIR/setup_scanner_cli.sh${NC}"
    echo -e "${YELLOW}Installation directory: $INSTALL_DIR${NC}"
    echo -e "${YELLOW}Please verify the installation completed successfully${NC}"
    exit 1
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
