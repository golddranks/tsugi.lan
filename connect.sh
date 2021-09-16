#!/bin/sh -eu

echo "Note: the router must NOT be connected to the upstream router via LAN, otherwise it won't function as a main DHCP server, and you have hard time connecting to it!"

echo ""

CURRENT_IP=${1:-192.168.1.1}
# Make the router to play together as a host in a DHCP network

ssh -o StrictHostKeyChecking=no "root@${CURRENT_IP}" <<EOF

uci set network.lan.proto='dhcp'
uci delete network.lan.ipaddr
uci delete network.lan.netmask
uci delete network.lan.ip6assign

uci commit network
reload_config
EOF

echo "You should now connect the router to the upstream router via a LAN port and run ./install.sh."