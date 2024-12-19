#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_error() {
    echo -e "${RED}[!] $1${NC}"
}

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

detect_cpu() {
    if [[ $(uname -p) == "arm" ]] || [[ $(uname -m) == "arm64" ]] || [[ $(uname -m) == "aarch64" ]]; then
        echo "arm"
    else
        echo "intel"
    fi
}

cleanup() {
    print_message "Cleaning up temporary files..."
    rm -f infera-*.sh
}

check_points() {
    curl http://localhost:11025/points | jq
}

create_update_service() {
    print_message "Creating update service..."
    
    cat > /usr/local/bin/infera-update.sh << 'EOL'
#!/bin/bash
screen -X -S infera_worker quit
sleep 2
rm -rf ~/infera
if [[ $(uname -m) == "arm64" ]]; then
    curl -O https://raw.githubusercontent.com/inferanetwork/install-scripts/refs/heads/main/infera-apple-m.sh
    chmod +x ./infera-apple-m.sh
    ./infera-apple-m.sh
else
    curl -O https://raw.githubusercontent.com/inferanetwork/install-scripts/refs/heads/main/infera-linux-intel.sh
    chmod +x ./infera-linux-intel.sh
    ./infera-linux-intel.sh
fi
screen -dmS infera_worker ~/infera
EOL

    chmod +x /usr/local/bin/infera-update.sh

    cat > /etc/systemd/system/infera-update.service << EOL
[Unit]
Description=Infera Node Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/infera-update.sh
User=$USER

[Install]
WantedBy=multi-user.target
EOL

    cat > /etc/systemd/system/infera-update.timer << EOL
[Unit]
Description=Run Infera Node Update Daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOL

    systemctl daemon-reload
    systemctl enable infera-update.timer
    systemctl start infera-update.timer
    
    print_message "Update service installed and scheduled for daily updates"
}

remove_update_service() {
    print_message "Removing update service..."
    systemctl stop infera-update.timer
    systemctl disable infera-update.timer
    rm -f /etc/systemd/system/infera-update.timer
    systemctl stop infera-update.service
    systemctl disable infera-update.service
    rm -f /etc/systemd/system/infera-update.service
    rm -f /usr/local/bin/infera-update.sh
    systemctl daemon-reload
}

remove_node() {
    print_message "Removing Infera node..."
    screen -X -S infera_worker quit 2>/dev/null
    systemctl stop ollama 2>/dev/null
    systemctl disable ollama 2>/dev/null
    remove_update_service
    rm -rf ~/infera
    rm -rf ~/.ollama
    print_message "Node removed successfully!"
    exit 0
}

update_node() {
    print_message "Starting node update process..."
    /usr/local/bin/infera-update.sh
    print_message "Update complete! Use 'screen -r infera_worker' to check node status"
    exit 0
}

echo "Please select an action:"
echo "1. Install node"
echo "2. Check points"
echo "3. Remove node"
echo "4. Update node"
read -p "Enter your choice (1/2/3/4): " action_choice

case $action_choice in
    2)
        check_points
        exit 0
        ;;
    3)
        remove_node
        ;;
    4)
        update_node
        ;;
    1)
        ;;
    *)
        print_error "Invalid choice. Exiting."
        exit 1
        ;;
esac

print_message "Updating system and installing dependencies..."
if [[ $(detect_os) == "macos" ]]; then
    if ! command -v brew &> /dev/null; then
        print_message "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew update
    brew install curl wget jq screen
else
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget jq screen
fi

print_message "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

if [[ $(detect_os) == "linux" ]]; then
    print_message "Starting Ollama service..."
    systemctl start ollama
    sleep 5
fi

OS_TYPE=$(detect_os)
CPU_TYPE=$(detect_cpu)

print_message "Detected system: $OS_TYPE with $CPU_TYPE CPU"
echo "Please confirm installation type:"
echo "1. MacOS/Apple Silicon"
echo "2. Linux/Intel"
read -p "Enter your choice (1/2): " choice

case $choice in
    1)
        print_message "Installing for MacOS/Apple Silicon..."
        INSTALL_SCRIPT="https://raw.githubusercontent.com/inferanetwork/install-scripts/refs/heads/main/infera-apple-m.sh"
        ;;
    2)
        print_message "Installing for Linux/Intel..."
        INSTALL_SCRIPT="https://raw.githubusercontent.com/inferanetwork/install-scripts/refs/heads/main/infera-linux-intel.sh"
        ;;
    *)
        print_error "Invalid choice. Exiting."
        cleanup
        exit 1
        ;;
esac

print_message "Downloading installation script..."
curl -O $INSTALL_SCRIPT
chmod +x infera-*.sh

print_message "Running installation script..."
./infera-*.sh

if [[ $OS_TYPE == "macos" ]]; then
    if ! grep -q "alias init-infera='~/infera'" ~/.zshrc; then
        echo "alias init-infera='~/infera'" >> ~/.zshrc
    fi
    source ~/.zshrc
else
    if ! grep -q "alias init-infera='~/infera'" ~/.bashrc; then
        echo "alias init-infera='~/infera'" >> ~/.bashrc
    fi
    source ~/.bashrc
fi

cleanup

if [ ! -f ~/infera ]; then
    print_error "Installation failed: infera executable not found"
    exit 1
fi

chmod +x ~/infera

print_message "Setting up auto-update service..."
create_update_service

print_message "Installation complete!"
print_message "Starting Infera node in screen session..."

screen -dmS infera_worker ~/infera

print_message "Installation and startup complete!"
print_message "Use 'screen -r infera_worker' to check node status"
print_message "Use Ctrl+A, D to detach from screen"
print_message "Auto-update service will run daily"
echo
print_message "You can check node status and manage it using these commands:"
echo "- View node: screen -r infera_worker"
echo "- Check points: curl http://localhost:11025/points | jq"
echo "- Available models:"
echo "  gemma:latest"
echo "  gemma2:latest"
echo "  dolphin-mistral:latest"
echo "  mistral:latest"
echo "  llama3:latest"
echo "  llama3.1:latest"
echo "  llama2-uncensored:latest"
echo
print_message "You can manage your node through web interface at:"
echo "http://YOUR_IP:11025/docs"