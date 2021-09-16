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


# Lan IPv6

uci set network.lan6=interface
uci set network.lan6.proto='dhcpv6'
uci set network.lan6.device='br-lan'
uci set network.lan6.ifaceid='::2'

# MacOS NDP+RA IPv6 address selection supports only LLA source addresses, so don't use ULA:
uci set network.globals.ula_prefix=''
uci commit network


# Add lan6 to trusted zone
uci delete firewall.cfg02dc81.network
uci add_list firewall.cfg02dc81.network='lan'
uci add_list firewall.cfg02dc81.network='lan6'
uci commit firewall

# Set LAN to relay mode to support NDP+RA based IPv6 addressing
uci set dhcp.lan.ignore='1'
uci commit dhcp

# Wifi
# Note the 2.5Ghz and 5Ghz radio numbers are the other way around as mon!
uci set wireless.default_radio0.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.default_radio1.ssid='Skeletor 5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='JP'
uci commit wireless

# General system settings
uci set system.cfg01e48a.hostname='tsugi'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system

/etc/init.d/odhcpd disable
/etc/init.d/firewall disable
/etc/init.d/dnsmasq disable

echo "Basic network config done."

echo "Start installing external packages."

opkg update

echo "Updated packet list."

PACKAGES=$(opkg list-upgradable | cut -f 1 -d ' ')
if [ -n "$PACKAGES" ]; then
    opkg upgrade "$PACKAGES"
fi

echo "Base packages upgraded"

opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils

echo "Utilities installed."

# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

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

cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan1 wps_pbc
hostapd_cli -i wlan1 wps_get_status
EOF
chmod 0755 /root/wps.sh

echo "WPS settings done."

reload_config
