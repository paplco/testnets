#!/bin/bash

YOUR_KEY_NAME=$1
YOUR_NAME=$2
DAEMON=regen
DENOM=uregen
CHAIN_ID=regen-redwood-1
LEAD_NODE_IP=209.182.218.23
LEAD_NODE_ID=61f53f226a4a71968a87583f58902405e289b4b9
PERSISTENT_PEERS="${LEAD_NODE_ID}@${LEAD_NODE_IP}:26656"

command_exists () {
    type "$1" &> /dev/null ;
}

if command_exists go ; then
    echo "Golang is already installed"
else
  echo "Install dependencies"
  sudo apt update
  sudo apt install build-essential jq -y

  wget https://dl.google.com/go/go1.15.2.linux-amd64.tar.gz
  tar -xvf go1.15.2.linux-amd64.tar.gz
  sudo mv go /usr/local

  echo "" >> ~/.profile
  echo 'export GOPATH=$HOME/go' >> ~/.profile
  echo 'export GOROOT=/usr/local/go' >> ~/.profile
  echo 'export GOBIN=$GOPATH/bin' >> ~/.profile
  echo 'export PATH=$PATH:~/.$DAEMON/cosmovisor/current/bin:/usr/local/go/bin:$GOBIN' >> ~/.profile

  #source ~/.profile
  . ~/.profile

  go version
fi

echo "-- Clear old data and install Regen-ledger and setup the node --"

rm -rf ~/.$DAEMON

echo "install regen-ledger"
git clone https://github.com/regen-network/regen-ledger $GOPATH/src/github.com/regen-network/regen-ledger
cd $GOPATH/src/github.com/regen-network/regen-ledger
git fetch
git checkout v1.0.0
make install

echo "Creating keys"
$DAEMON keys add $YOUR_KEY_NAME

echo ""
echo "After you have copied the mnemonic phrase in a safe place,"
echo "press the space bar to continue."
read -s -d ' '
echo ""

echo "Setting up your validator"
$DAEMON init --chain-id $CHAIN_ID $YOUR_NAME
curl http://$LEAD_NODE_IP:26657/genesis | jq .result.genesis > ~/.$DAEMON/config/genesis.json


echo "----------Setting config for seed node---------"
sed -i 's#tcp://127.0.0.1:26657#tcp://0.0.0.0:26657#g' ~/.$DAEMON/config/config.toml
sed -i '/persistent_peers =/c\persistent_peers = "'"$PERSISTENT_PEERS"'"' ~/.$DAEMON/config/config.toml

DAEMON_PATH=$(which $DAEMON)

echo "Installing cosmovisor - an upgrade manager..."

rm -rf $GOPATH/src/github.com/cosmos/cosmos-sdk
git clone https://github.com/cosmos/cosmos-sdk $GOPATH/src/github.com/cosmos/cosmos-sdk
cd $GOPATH/src/github.com/cosmos/cosmos-sdk
git checkout v0.40.0
cd cosmovisor
make cosmovisor
cp cosmovisor $GOBIN/cosmovisor

echo "Setting up cosmovisor directories"
mkdir -p ~/.$DAEMON/cosmovisor
mkdir -p ~/.$DAEMON/cosmovisor/genesis/bin
cp $GOBIN/$DAEMON ~/.$DAEMON/cosmovisor/genesis/bin

echo "---------Creating system file---------"

echo "[Unit]
Description=Cosmovisor daemon
After=network-online.target
[Service]
Environment="DAEMON_NAME=${DAEMON}"
Environment="DAEMON_HOME=${HOME}/.${DAEMON}"
Environment="DAEMON_RESTART_AFTER_UPGRADE=on"
User=${USER}
ExecStart=${GOBIN}/cosmovisor start
Restart=always
RestartSec=3
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
" >cosmovisor.service

sudo mv cosmovisor.service /lib/systemd/system/cosmovisor.service
sudo -S systemctl daemon-reload
sudo -S systemctl start cosmovisor

echo
echo "To see your account address, enter passphrase."
ACCOUNT_ADDR=$($DAEMON keys show $YOUR_KEY_NAME -a)
echo "Account address: ${ACCOUNT_ADDR}"
echo "Your node setup is done. You would need some tokens to start your validator. You can get some tokens from the faucet:"
echo "http://${LEAD_NODE_IP}:8000/faucet/${ACCOUNT_ADDR}"
echo
echo
echo "After receiving tokens, you can create your validator by running"
echo "$DAEMON tx staking create-validator --amount 9000000000$DENOM --commission-max-change-rate \"0.1\" --commission-max-rate \"0.20\" --commission-rate \"0.1\" --details \"Some details about yourvalidator\" --from $YOUR_KEY_NAME   --pubkey=\"$($DAEMON tendermint show-validator)\" --moniker $YOUR_NAME --min-self-delegation \"1\" --chain-id $CHAIN_ID --node http://${LEAD_NODE_IP}:26657"
echo
