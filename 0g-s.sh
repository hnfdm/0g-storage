#!/bin/bash

# Prompt for private key at the start
echo -e "\033[34mEnter your private key: \033[0m"
read -s PRIVATE_KEY
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "\033[31mError: Private key cannot be empty.\033[0m"
    exit 1
fi

# Step 1: Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y clang cmake build-essential openssl pkg-config libssl-dev

# Step 2: Install Go (skip if already installed)
if ! command -v go &> /dev/null; then
    echo "Installing Go..."
    cd $HOME
    ver="1.22.0"
    wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
    rm "go$ver.linux-amd64.tar.gz"
    echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
    source ~/.bash_profile
    go version
else
    echo "Go is already installed, skipping..."
fi

# Step 3: Install rustup (skip if already installed)
if ! command -v rustup &> /dev/null; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
else
    echo "rustup is already installed, skipping..."
fi

# Step 4: Download and build 0g-storage-node
echo "Downloading and building 0g-storage-node..."
cd $HOME
rm -rf 0g-storage-node
git clone https://github.com/0glabs/0g-storage-node.git
cd 0g-storage-node
git checkout v0.8.4
git submodule update --init
cargo build --release || { echo -e "\033[31mBuild failed.\033[0m"; exit 1; }

# Step 5: Download config file
echo "Downloading configuration file..."
wget -O $HOME/0g-storage-node/run/config-testnet-turbo.toml https://josephtran.co/config-testnet-turbo.toml

# Step 6: Set miner key
echo "Setting miner key..."
sed -i "s|^\s*#\?\s*miner_key\s*=.*|miner_key = \"$PRIVATE_KEY\"|" $HOME/0g-storage-node/run/config-testnet-turbo.toml
echo -e "\033[32mPrivate key has been successfully added to the config file.\033[0m"

# Step 7: Verify configuration
echo "Verifying configuration changes..."
grep -E "^(network_dir|network_enr_address|network_enr_tcp_port|network_enr_udp_port|network_libp2p_port|network_discovery_port|rpc_listen_address|rpc_enabled|db_dir|log_config_file|log_contract_address|mine_contract_address|reward_contract_address|log_sync_start_block_number|blockchain_rpc_endpoint|auto_sync_enabled|find_peer_timeout)" $HOME/0g-storage-node/run/config-testnet-turbo.toml

# Step 8: Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config-testnet-turbo.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Step 9: Start node
echo "Starting node..."
sudo systemctl daemon-reload
sudo systemctl enable zgs
sudo systemctl restart zgs
sudo systemctl status zgs

# Step 10: Display log command
echo -e "\033[32mSetup complete. To check logs, run:\033[0m"
echo "tail -f ~/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
