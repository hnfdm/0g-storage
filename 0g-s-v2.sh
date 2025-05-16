#!/bin/bash

# Prompt for miner_key at the beginning
read -p "Enter your miner_key: " miner_key
if [ -z "$miner_key" ]; then
    echo "Error: miner_key cannot be empty"
    exit 1
fi

# Function to check if a package is installed
check_package() {
    if dpkg -l | grep -q "$1"; then
        echo "$1 is already installed"
        return 0
    else
        return 1
    fi
}

# Function to check if Rust is installed
check_rust() {
    if command -v rustc &> /dev/null; then
        echo "Rust is already installed"
        return 0
    else
        return 1
    fi
}

echo "Updating package lists..."
sudo apt-get update

echo "Checking and installing necessary packages..."
for pkg in clang cmake build-essential openssl pkg-config libssl-dev; do
    if ! check_package "$pkg"; then
        echo "Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
done

echo "Checking and installing Rust..."
if ! check_rust; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    source "$HOME/.cargo/env"
fi

echo "Removing existing 0g-storage-node directory if it exists..."
if [ -d "$HOME/0g-storage-node" ]; then
    sudo systemctl stop zgs &> /dev/null
    rm -rf "$HOME/0g-storage-node"
fi

echo "Cloning the repository..."
git clone -b v0.8.4 https://github.com/0glabs/0g-storage-node.git
cd "$HOME/0g-storage-node"

echo "Stashing any local changes..."
git stash

echo "Fetching all tagsลง..."
git fetch --all --tags

echo "Checking out specific commit..."
git checkout 40d4355

echo "Updating submodules..."
git submodule update --init

echo "Building the project..."
cargo build --release

echo "Removing old config file if it exists..."
[ -f "$HOME/0g-storage-node/run/config.toml" ] && rm "$HOME/0g-storage-node/run/config.toml"

echo "Downloading new config file..."
curl -o "$HOME/0g-storage-node/run/config.toml" https://raw.githubusercontent.com/zstake-xyz/test/refs/heads/main/0g_storage_config.toml

echo "Updating miner_key in config.toml..."
sed -i "s/miner_key = \".*\"/miner_key = \"$miner_key\"/" "$HOME/0g-storage-node/run/config.toml"

echo "Creating systemd service file..."
sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon, enabling and starting the service..."
sudo systemctl daemon-reload && sudo systemctl enable zgs && sudo systemctl start zgs

echo "Starting monitoring loop..."
while true; do 
    response=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
    logSyncHeight=$(echo "$response" | jq '.result.logSyncHeight')
    connectedPeers=$(echo "$response" | jq '.result.connectedPeers')
    echo -e "logSyncHeight: \033[32m$logSyncHeight\033[0m, connectedPeers: \033[34m$connectedPeers\033[0m"
    sleep 5
done
