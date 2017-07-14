#!/bin/bash
#version 0.89-N/HS-I

#You may share this script but a reference to RaspberryConnect.com must be included in copies or derivatives of this script. 

#Wifi & Hotspot with Internet
#A script to switch between a wifi network and an Internet routed Hotspot
#Raspberry Pi with a network port required for Internet in hotspot mode.
#Works at startup or with a seperate timer or manually without a reboot
#Other setup required find out more at
#http://www.raspberryconnect.com

device="wlan0" # the device ID of your WiFi card
hotspotIP="10.0.0.1/24" #the IP addres / subnet when in hotspot mode


IFSdef=$IFS

#These four lines capture the wifi networks the RPi is setup to use
wpassid=$(awk '/ssid="/{ print $0 }' /etc/wpa_supplicant/wpa_supplicant.conf | awk -F'ssid=' '{ print $2 }' ORS=',' | sed 's/\"/''/g' | sed 's/,$//')
IFS=","
ssids=($wpassid)
IFS=$IFSdef #reset back to defaults


#Note:If you only want to check for certain SSIDs
#Remove the # in in front of ssids=('mySSID1'.... below and put a # infront of all four lines above
# separated by a space, eg ('mySSID1' 'mySSID2')
#ssids=('mySSID1' 'mySSID2' 'mySSID3')

#Enter the Routers Mac Addresses for hidden SSIDs, seperated by spaces ie 
#( '11:22:33:44:55:66' 'aa:bb:cc:dd:ee:ff' ) 
mac=()

ssidsmac=("${ssids[@]}" "${mac[@]}") #combines ssid and MAC for checking

createAdHocNetwork()
{
    ip link set dev $device down
    ip a add $hotspotIP brd + dev $device
    ip link set dev $device up
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o $device -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i $device -o eth0 -j ACCEPT
    systemctl start dnsmasq
    systemctl start hostapd
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

KillHotspot()
{
    echo "Shutting Down Hotspot"
    ip link set dev $device down
    systemctl stop hostapd
    systemctl stop dnsmasq
    iptables -D FORWARD -i eth0 -o $device -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -D FORWARD -i $device -o eth0 -j ACCEPT
    echo 0 > /proc/sys/net/ipv4/ip_forward
    ip addr flush dev $device
    ip link set dev $device up
}

ChkWifiUp()
{
        sleep 10 #give tine for ip to be assigned by router
	if ! wpa_cli status | grep 'ip_address' >/dev/null 2>&1
        then #Failed to connect to wifi (check your wifi settings, password etc)
	       echo 'Wifi failed to connect, falling back to Hotspot'
               wpa_cli terminate >/dev/null 2>&1
	       createAdHocNetwork
	fi
}

#Check to see what SSID's and MAC addresses are in range
ssidChk=('NoSSid')
for ssid in "${ssidsmac[@]}"
do
     if { iw dev $device scan ap-force | grep "$ssid"; } >/dev/null 2>&1
     then
              ssidChk=$ssid
              break
       else
              ssidChk='NoSSid'
     fi
done

#Create Hotspot or connect to valid wifi networks
if [ $ssidChk != "NoSSid" ] 
then
       echo 'Using SSID:' $ssidChk
       echo 0 > /proc/sys/net/ipv4/ip_forward #deactivate ip forwarding
       if systemctl status hostapd | grep "(running)" >/dev/null 2>&1
       then #hotspot running and ssid in range
              KillHotspot
              echo "Hotspot Deactivated, Bringing Wifi Up"
              wpa_supplicant -B -i $device -c /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null 2>&1
              ChkWifiUp
       elif { wpa_cli status | grep 'ip_address'; } >/dev/null 2>&1
       then #Already connected
              echo "Wifi already connected to a network"
       else #ssid exists and no hotspot running connect to wifi network
              echo "Connecting to the WiFi Network"
              wpa_supplicant -B -i $device -c /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null 2>&1
              ChkWifiUp
       fi
else #ssid or MAC address not in range
       if systemctl status hostapd | grep "(running)" >/dev/null 2>&1
       then
              echo "Hostspot already active"
       elif { wpa_cli status | grep '$device'; } >/dev/null 2>&1
       then
              echo "Cleaning wifi files and Activating Hotspot"
              wpa_cli terminate >/dev/null 2>&1
              ip addr flush $device
              ip link set dev $device down
              rm -r /var/run/wpa_supplicant >/dev/null 2>&1
              createAdHocNetwork
       else #"No SSID, activating Hotspot"
              createAdHocNetwork
       fi
fi
