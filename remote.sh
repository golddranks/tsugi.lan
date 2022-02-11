#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
WIFI_PW=${3:?}

. /etc/openwrt_release

echo "Setting up config on Buffalo WSR-1166DHP. OS: $DISTRIB_DESCRIPTION"

# Add the host pubkey of the installer host
echo "$SSH_PUBKEY" > /etc/dropbear/authorized_keys

# For convenience, add other common pubkeys
cat authorized_keys_strict >> /etc/dropbear/authorized_keys
rm authorized_keys_strict

passwd << EOF
$ROOT_PW
$ROOT_PW
EOF

uci set dropbear.cfg014dd4.RootPasswordAuth='off'
uci set dropbear.cfg014dd4.PasswordAuth='off'
uci set dropbear.cfg014dd4.Interface='lan'
uci commit dropbear

echo "Security config done."

# General system settings
uci set system.cfg01e48a.hostname='tsugi'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system


echo "Start installing external packages."

opkg update

echo "Updated packet list."

opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils

echo "Utilities installed."

# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

uci delete nginx._lan.listen || true
uci delete nginx._lan.uci_manage_ssl || true
uci add_list nginx._lan.listen='666 ssl default_server'
uci add_list nginx._lan.listen='[::]:666 ssl default_server'
uci set nginx._lan.ssl_certificate='/etc/ssl/tsugi.lan.chain.pem'
uci set nginx._lan.ssl_certificate_key='/etc/ssl/tsugi.lan.key'

uci commit nginx

echo "HTTPS enabled on web interface."

# Set up WPS
# It doesn't seem to work with two radios, so setting up only the 2.5Ghz one.
opkg remove wpad-basic-wolfssl
opkg install wpad-wolfssl hostapd-utils

uci set wireless.default_radio0.wps_pushbutton='1'
uci commit wireless

# NOTE: wlan0 is 2.5Ghz in case of Tsugi!
cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan0 wps_pbc
hostapd_cli -i wlan0 wps_get_status
EOF
chmod 0755 /root/wps.sh

echo "WPS settings done."


# Network config last, because it will disable network connectivity from WAN.

# This router is LAN only, so disabling DHCP, DNS, Firewall and deleting WAN interfaces
/etc/init.d/odhcpd disable
/etc/init.d/firewall disable
/etc/init.d/dnsmasq disable
uci delete network.wan || true
uci delete network.wan6 || true

# Vlan
# Delete br-lan, we are going to bridge the wan port too.
uci delete network.cfg030f15 || true
uci set network.br0=device
uci set network.br0.type='bridge'
uci set network.br0.name="br0"
uci set network.br0.vlan_filtering='1'
uci set network.br0.ports='lan1 lan2 lan3 lan4 wan'

# LAN VLAN 1 (LAN1 + LAN2 + LAN3 + LAN4 + ETH0)
uci set network.br_lan=bridge-vlan
uci set network.br_lan.device='br0'
uci set network.br_lan.vlan='1'
uci set network.br_lan.ports='lan1:t lan2 lan3 lan4'
uci set network.br_lan.local='1'

# JCOM WAN VLAN 3 (LAN1 + WAN)
uci set network.br_wan=bridge-vlan
uci set network.br_wan.device='br0'
uci set network.br_wan.vlan='3'
uci set network.br_wan.ports='lan1:t wan'
uci set network.br_wan.local='0'

# Lan
uci set network.lan.proto='dhcp'
uci set network.lan.device='br0.1'

uci set network.lan6=interface
uci set network.lan6.proto='dhcpv6'
uci set network.lan6.ifaceid='::2'
uci set network.lan6.device='br0.1'

uci set firewall.cfg02dc81.network='lan lan6'
uci commit firewall

# MacOS NDP+RA IPv6 address selection supports only LLA source addresses, so don't use ULA:
uci set network.globals.ula_prefix=''
uci commit network

# Wifi
# Note the 2.5Ghz and 5Ghz radio numbers are the other way around as mon!
uci set wireless.default_radio0.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.default_radio0.ieee80211r='1'
uci set wireless.default_radio0.mobility_domain='cc66'
uci set wireless.default_radio0.ft_over_ds='1'
uci set wireless.default_radio0.ft_psk_generate_local='1'
uci set wireless.radio0.cell_density='0'

uci set wireless.default_radio1.ssid='Skeletor 5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='JP'
uci set wireless.default_radio1.ieee80211r='1'
uci set wireless.default_radio1.mobility_domain='cc66'
uci set wireless.default_radio1.ft_over_ds='1'
uci set wireless.default_radio1.ft_psk_generate_local='1'
uci set wireless.radio1.cell_density='0'

uci commit wireless

echo "Basic network config done."

uci set dropbear.cfg014dd4.Port='222'
uci commit dropbear

reload_config
