#!/bin/sh -eu

CURRENT_IP=${1:-192.168.1.1}
CURRENT_PORT=${2:-22}

[ ! -d "../certs" ] && echo "Prepare ../certs directory" && exit 1
[ ! -d "../pubkeys" ] && echo "Prepare ../pubkeys directory" && exit 1

. ./secrets.sh
SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

# Sending the host key with SCP because the dropbear format is a binary format
echo "$DROPBEAR_HOST_KEY" | base64 --decode > dropbear_ed25519_host_key
echo "Attempting to connect."
scp -P "${CURRENT_PORT}" -o StrictHostKeyChecking=no dropbear_ed25519_host_key \
    "root@${CURRENT_IP}:/etc/dropbear/dropbear_ed25519_host_key"
rm dropbear_ed25519_host_key
ssh -p "${CURRENT_PORT}" -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "/etc/init.d/dropbear restart"

echo "Dropbear restarted."
ssh-keygen -R "${CURRENT_IP}"

# Logging in once to re-set the correct key on this host
ssh -p "${CURRENT_PORT}" -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "echo Works!"

# x509 certs for the admin panel are also unwieldy so let's SCP them
ssh -p "${CURRENT_PORT}" "root@${CURRENT_IP}" "mkdir -p /etc/ssl"
scp -P "${CURRENT_PORT}" ../certs/cert/tsugi.lan.key "root@${CURRENT_IP}:/etc/ssl/tsugi.lan.key"
scp -P "${CURRENT_PORT}" ../certs/cert/tsugi.lan.chain.pem "root@${CURRENT_IP}:/etc/ssl/tsugi.lan.chain.pem"

# Sending the install script
scp -P "${CURRENT_PORT}" remote.sh "root@${CURRENT_IP}:"

# Sending the authorized pub keys
scp -P "${CURRENT_PORT}" ../pubkeys/authorized_keys_strict "root@${CURRENT_IP}:"

# Running the install script
ssh -p "${CURRENT_PORT}" "root@${CURRENT_IP}" "./remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$WIFI_PW'"
echo "Booting."
ssh -p "${CURRENT_PORT}" "root@${CURRENT_IP}" "reboot now"
