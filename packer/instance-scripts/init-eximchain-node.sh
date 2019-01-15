#!/bin/bash
set -u -o pipefail

function wait_for_successful_command {
    local COMMAND=$1

    $COMMAND
    until [ $? -eq 0 ]
    do
        sleep 5
        $COMMAND
    done
}

function download_chain_metadata {
  local readonly DATADIR="main-network"
  curl https://raw.githubusercontent.com/Eximchain/eximchain-network-data/master/$DATADIR/quorum-genesis.json > /opt/quorum/private/quorum-genesis.json
  curl https://raw.githubusercontent.com/Eximchain/eximchain-network-data/master/$DATADIR/bootnodes.txt > /opt/quorum/info/bootnodes.txt
  curl https://raw.githubusercontent.com/Eximchain/eximchain-network-data/master/$DATADIR/constellation-bootnodes.txt > /opt/quorum/info/constellation-bootnodes.txt
}

function generate_eximchain_supervisor_config {
    local ADDRESS=$1
    local PASSWORD=$2
    local HOSTNAME=$3
    local CONSTELLATION_CONFIG=$4

    local NETID=$(cat /opt/quorum/info/network-id.txt)
    local BOOTNODE_LIST=$(cat /opt/quorum/info/bootnodes.txt)

    local VERBOSITY=4
    local PW_FILE="/tmp/geth-pw"
    local GLOBAL_ARGS="--networkid $NETID --rpc --rpcaddr $HOSTNAME --rpcapi admin,db,eth,debug,miner,net,shh,txpool,personal,web3,quorum --rpcport 22000 --rpccorsdomain \"*\" --port 21000 --verbosity $VERBOSITY --privateconfigpath $CONSTELLATION_CONFIG"

    # Assemble list of bootnodes
    local BOOTNODES=""
    for bootnode in ${BOOTNODE_LIST[@]}
    do
        BOOTNODES="$BOOTNODES,$bootnode"
    done
    BOOTNODES=${BOOTNODES:1}

    echo "$PASSWORD" > $PW_FILE
    ARGS="$GLOBAL_ARGS --unlock \"$ADDRESS\" --password \"$PW_FILE\" --bootnodes $BOOTNODES"

    local COMMAND="geth $ARGS"

    echo "[program:eximchain]
command=$COMMAND
stdout_logfile=/opt/quorum/log/eximchain-stdout.log
stderr_logfile=/opt/quorum/log/eximchain-error.log
numprocs=1
autostart=true
autorestart=false
stopsignal=INT
user=ubuntu" | sudo tee /etc/supervisor/conf.d/eximchain-supervisor.conf
}

function complete_constellation_config {
    local HOSTNAME=$1
    local CONSTELLATION_CONFIG_PATH=$2

    local BOOTNODES=$(cat /opt/quorum/info/constellation-bootnodes.txt)
    local OTHER_NODES=""

    # Configure constellation with bootnode IPs
    for bootnode in ${BOOTNODES[@]}
    do
        OTHER_NODES="$OTHER_NODES,\"http://$bootnode:9000/\""
    done
    OTHER_NODES=${OTHER_NODES:1}
    OTHER_NODES_LINE="othernodes = [$OTHER_NODES]"

    echo "$OTHER_NODES_LINE" >> $CONSTELLATION_CONFIG_PATH

    # Configure constellation with URL
    echo "url = \"http://$HOSTNAME:9000/\"" >> $CONSTELLATION_CONFIG_PATH
}

# Wait for operator to initialize and unseal vault
wait_for_successful_command 'vault init -check'
wait_for_successful_command 'vault status'

# Wait for vault to be fully configured by the root user
wait_for_successful_command 'vault auth -method=aws'

download_chain_metadata

# Load Address, Password, and Key if we already generated them or generate new ones if none exist
NODE_INDEX=$(cat /opt/quorum/info/node-index.txt)
ADDRESS=$(vault read -field=address nodes/$NODE_INDEX/addresses)
if [ $? -eq 0 ]
then
    # Address is already in vault and this is a replacement instance.  Load info from vault
    GETH_PW=$(wait_for_successful_command "vault read -field=geth_pw nodes/$NODE_INDEX/passwords")
    CONSTELLATION_PW=$(wait_for_successful_command "vault read -field=constellation_pw nodes/$NODE_INDEX/passwords")
    # Generate constellation key files
    wait_for_successful_command "vault read -field=constellation_pub_key nodes/$NODE_INDEX/addresses" > /opt/quorum/constellation/private/constellation.pub
    wait_for_successful_command "vault read -field=constellation_priv_key nodes/$NODE_INDEX/keys" > /opt/quorum/constellation/private/constellation.key
    # Generate geth key file
    GETH_KEY_FILE_NAME=$(wait_for_successful_command "vault read -field=geth_key_file nodes/$NODE_INDEX/keys")
    GETH_KEY_FILE_DIR="/home/ubuntu/.ethereum/keystore"
    mkdir -p $GETH_KEY_FILE_DIR
    GETH_KEY_FILE_PATH="$GETH_KEY_FILE_DIR/$GETH_KEY_FILE_NAME"
    wait_for_successful_command "vault read -field=geth_key nodes/$NODE_INDEX/keys" > $GETH_KEY_FILE_PATH
elif [ -e /home/ubuntu/.ethereum/keystore/* ]
then
    # Address was created but not stored in vault. This is a process reboot after a previous failure.
    # Load address from file and password from vault
    GETH_PW=$(wait_for_successful_command "vault read -field=geth_pw nodes/$NODE_INDEX/passwords")
    CONSTELLATION_PW=$(wait_for_successful_command "vault read -field=constellation_pw nodes/$NODE_INDEX/passwords")
    ADDRESS=0x$(cat /home/ubuntu/.ethereum/keystore/* | jq -r .address)
    # Generate constellation keys if they weren't generated last run
    if [ ! -e /opt/quorum/constellation/private/constellation.* ]
    then
        echo "$CONSTELLATION_PW" | constellation-node --generatekeys=/opt/quorum/constellation/private/constellation
    fi
else
    # This is the first run, generate a new key and password
    GETH_PW=$(uuidgen -r)
    # TODO: Get non-empty passwords to work
    CONSTELLATION_PW=""
    # Store the password first so we don't lose it
    wait_for_successful_command "vault write nodes/$NODE_INDEX/passwords geth_pw=\"$GETH_PW\" constellation_pw=\"$CONSTELLATION_PW\""
    # Generate the new key pair
    ADDRESS=0x$(echo -ne "$GETH_PW\n$GETH_PW\n" | geth account new | grep Address | awk '{ gsub("{|}", "") ; print $2 }')
    # Generate constellation keys
    echo "$CONSTELLATION_PW" | constellation-node --generatekeys=/opt/quorum/constellation/private/constellation
fi
CONSTELLATION_PUB_KEY=$(cat /opt/quorum/constellation/private/constellation.pub)
CONSTELLATION_PRIV_KEY=$(cat /opt/quorum/constellation/private/constellation.key)
HOSTNAME=$(wait_for_successful_command 'curl http://169.254.169.254/latest/meta-data/public-hostname')
PRIV_KEY=$(cat /home/ubuntu/.ethereum/keystore/*$(echo $ADDRESS | cut -d 'x' -f2))
PRIV_KEY_FILENAME=$(ls /home/ubuntu/.ethereum/keystore/)

# Write key and address into the vault
wait_for_successful_command "vault write nodes/$NODE_INDEX/keys geth_key=$PRIV_KEY geth_key_file=$PRIV_KEY_FILENAME constellation_priv_key=$CONSTELLATION_PRIV_KEY"
wait_for_successful_command "vault write nodes/$NODE_INDEX/addresses address=$ADDRESS constellation_pub_key=$CONSTELLATION_PUB_KEY hostname=$HOSTNAME"

complete_constellation_config $HOSTNAME /opt/quorum/constellation/config.conf

# Initialize geth to run on the quorum network
geth init /opt/quorum/private/quorum-genesis.json

# Sleep to let constellation bootnodes start first
sleep 30

# Run Constellation
sudo mv /opt/quorum/private/constellation-supervisor.conf /etc/supervisor/conf.d/
sudo supervisorctl reread
sudo supervisorctl update

# Sleep to let constellation-node start
sleep 5

# Generate supervisor config to run quorum
generate_eximchain_supervisor_config $ADDRESS $GETH_PW $HOSTNAME /opt/quorum/constellation/config.conf

# Remove the config that runs this and run quorum
sudo rm /etc/supervisor/conf.d/init-eximchain-node-supervisor.conf
sudo supervisorctl reread
sudo supervisorctl update
