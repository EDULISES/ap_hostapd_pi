#!/bin/bash
# Description: The script setup a Access Point into the Raspberry
# PI 3 with HOSTAPD. For more information about the configuration
# please see:
# https://frillip.com/using-your-raspberry-pi-3-as-a-wifi-access-point-with-hostapd/
# Author: Ing. Edward U. Benitez Rendon
# Date: 20-07-17

if [ "$EUID" -ne 0 ];	then 
	echo "Must be root"
	exit
fi

if [[ $# -lt 1 ]]; then
	echo "You need to pass a password!"
	echo "Example:"
	echo "sudo $0 yourChosenPassword [apName]"
	exit
fi

AP_PSW="$1"
AP_SSID="rPi3"

if [[ $# -eq 2 ]]; then
	AP_SSID=$2
fi

# Install HOSTAPD
apt-get install dnsmasq hostapd -y

# Tell to dhcpcd that ignore wlan0 for let us configure it with static IP address
echo "denyinterfaces wlan0" >> /etc/dhcpcd.conf

# Delete old wlan0 configuration
sed -i -- 's/allow-hotplug wlan0//g' /etc/network/interfaces
sed -i -- 's/iface wlan0 inet manual//g' /etc/network/interfaces
sed -i -- 's/    wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf//g' /etc/network/interfaces

# Add the new confguration for wlan0
cat >> /etc/network/interfaces <<EOF
# Added by setup script for access point
allow-hotplug wlan0
iface wlan0 inet static
	address 172.24.1.1
	netmask 255.255.255.0
	network 172.24.1.0
	broadcast 172.24.1.255
EOF

# Restart dhcpcd service
service dhcpcd restart
# Reload the configuration for wlan0
ifdown wlan0
ifup wlan0

cat > /etc/hostapd/hostapd.conf <<EOF
# This is the name of the WiFi interface we configured above
interface=wlan0

# Use the nl80211 driver with the brcmfmac driver
driver=nl80211

# This is the name of the network
ssid=$AP_SSID

# Use the 2.4GHz band
hw_mode=g

# Use channel 6
channel=6

# Enable 802.11n
ieee80211n=1

# Enable WMM
wmm_enabled=1

# Enable 40MHz channels with 20ns guard interval
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

# Accept all MAC addresses
macaddr_acl=0

# Use WPA authentication
auth_algs=1

# Require clients to know the network name
ignore_broadcast_ssid=0

# Use WPA2
wpa=2

# Use a pre-shared key
wpa_key_mgmt=WPA-PSK

# The network passphrase
wpa_passphrase=$AP_PSW

# Use AES, instead of TKIP
rsn_pairwise=CCMP
EOF
# Set the path for config file
sed -i -- 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/g' /etc/default/hostapd

# Config dnsmasq.conf, rename the old file because has innecesary information and
# create a new file with essential config
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0      # Use interface wlan0  
listen-address=172.24.1.1 # Explicitly specify the address to listen on  
bind-interfaces      # Bind to the interface to make sure we aren't sending things elsewhere  
server=8.8.8.8       # Forward DNS requests to Google DNS  
domain-needed        # Don't forward short names  
bogus-priv           # Never forward addresses in the non-routed address spaces.  
dhcp-range=172.24.1.50,172.24.1.150,12h # Assign IP addresses between 172.24.1.50 and 172.24.1.150 with a 12 hour lease time 
EOF

# Send traffic anywhere it to enable packet forwarding
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
EOF

# Share our Internet connection to our devices connected over WiFi by the 
# configuring a NAT between our wlan0 interface and our eth0 interface.
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save the iptables rules in a file
sh -c "iptables-save > /etc/iptables.ipv4.nat"

# We need to run the file after each reboot
sed -i '$ i\iptables-restore < \/etc\/iptables.ipv4.nat \n' /etc/rc.local

systemctl enable hostapd

echo "All done! Please reboot"