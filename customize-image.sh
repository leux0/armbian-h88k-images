#!/bin/bash

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
		jammy)
			# your code here
			;;
		noble)
			# your code here
			;;
		trixie)
			# your code here
			;;
		bullseye)
			# your code here
			;;
		bookworm)
			# your code here
			InstallWirelessRouter
			InstallQuectel-CM
			GetFirmwareMali
			;;
	esac
} # Main

InstallWirelessRouter() {
	# 安装所需软件及其依赖
	apt update && apt-get install -yy dnsmasq hostapd bridge-utils ifupdown iptables wireless-regdb
	# 跳过首次脚本（默认用户密码：root:1234）
	rm /root/.not_logged_in_yet
	# 禁网卡重命名，开启内核转发，修改HOSTAPD默认配置文件路径
	echo "extraboardargs=net.ifnames=0" >> /boot/armbianEnv.txt
	sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/" /etc/sysctl.conf
	sed -i "s/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/" /etc/sysctl.conf
	sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

	# 设置网桥及转发规则
	cat << EOF >> /etc/network/interfaces
auto br-lan
iface br-lan inet static
  address 192.168.1.1
  bridge_ports eth1 eth2
up iptables -t nat -A POSTROUTING -s 192.168.1.1/24 -o wwan0 -j MASQUERADE

iface br-lan inet6 static
  address fd00::1
  netmask 64
up ip6tables -t nat -A POSTROUTING -s fd00::1/64 -o wwan0 -j MASQUERADE
EOF

	# 写入DNSMASQ配置
	cat << EOF >> /etc/dnsmasq.conf
no-resolv
interface=br-lan
listen-address=::1,127.0.0.1,192.168.1.1
server=223.5.5.5
server=223.6.6.6
server=240C::6666
server=240C::6644
dhcp-range=br-lan,192.168.1.100,192.168.1.249,255.255.255.0,24h
enable-ra
dhcp-range=br-lan,::1,constructor:br-lan,ra-names,24h
EOF

	# 如下适用MT7916发射5G 80MHZ开启WiFi6
	cat << EOF > /etc/hostapd/hostapd.conf
driver=nl80211
country_code=US
interface=wlan1
bridge=br-lan
hw_mode=a
channel=36

auth_algs=1
wpa=2
ssid=H88K
utf8_ssid=1
wpa_pairwise=CCMP
ignore_broadcast_ssid=0
wpa_passphrase=1234567890
wpa_key_mgmt=WPA-PSK WPA-PSK-SHA256 SAE

ieee80211w=1
ieee80211d=1
ieee80211h=1
wmm_enabled=1

tx_queue_data2_burst=2.0
ieee80211n=1
ht_capab=[HT40+][LDPC][SHORT-GI-20][SHORT-GI-40][TX-STBC][RX-STBC1][MAX-AMSDU-7935]
ieee80211ac=1
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
vht_capab=[RXLDPC][SHORT-GI-80][SHORT-GI-160][TX-STBC-2BY1][SU-BEAMFORMER][SU-BEAMFORMEE][MU-BEAMFORMER][MU-BEAMFORMEE][RX-ANTENNA-PATTERN][TX-ANTENNA-PATTERN][RX-STBC-1][SOUNDING-DIMENSION-3][BF-ANTENNA-4][VHT160][MAX-MPDU-11454][MAX-A-MPDU-LEN-EXP7]
ieee80211ax=1
he_oper_chwidth=1
he_oper_centr_freq_seg0_idx=42
he_su_beamformer=1
he_mu_beamformer=1
he_default_pe_duration=4
he_rts_threshold=1023
he_mu_edca_qos_info_param_count=0
he_mu_edca_qos_info_q_ack=0
he_mu_edca_qos_info_queue_request=0
he_mu_edca_qos_info_txop_request=0
he_mu_edca_ac_be_aifsn=8
he_mu_edca_ac_be_aci=0
he_mu_edca_ac_be_ecwmin=9
he_mu_edca_ac_be_ecwmax=10
he_mu_edca_ac_be_timer=255
he_mu_edca_ac_bk_aifsn=15
he_mu_edca_ac_bk_aci=1
he_mu_edca_ac_bk_ecwmin=9
he_mu_edca_ac_bk_ecwmax=10
he_mu_edca_ac_bk_timer=255
he_mu_edca_ac_vi_ecwmin=5
he_mu_edca_ac_vi_ecwmax=7
he_mu_edca_ac_vi_aifsn=5
he_mu_edca_ac_vi_aci=2
he_mu_edca_ac_vi_timer=255
he_mu_edca_ac_vo_aifsn=5
he_mu_edca_ac_vo_aci=3
he_mu_edca_ac_vo_ecwmin=5
he_mu_edca_ac_vo_ecwmax=7
he_mu_edca_ac_vo_timer=255
EOF

	# 用支持AX的hostapd版本替换原来的
	wget -O /usr/sbin/hostapd http://leux.cn/dl/hostapd
	wget -O /usr/sbin/hostapd_cli http://leux.cn/dl/hostapd_cli
	chmod 755 /usr/sbin/hostapd
	chmod 755 /usr/sbin/hostapd_cli

	# 关闭systemd自带的网络管理，并设置ifupdown开机自启
	systemctl disable systemd-networkd
	systemctl mask systemd-networkd
	systemctl enable networking
	# 关闭占用53端口的项目，并设置DNSMASQ开机自启
	systemctl disable systemd-resolved
	systemctl enable dnsmasq
	# 关闭其他无线占用并设置软件开机自启
	systemctl disable wpa_supplicant
	systemctl unmask hostapd
	systemctl enable hostapd

} # InstallWirelessRouter

InstallQuectel-CM() {
	wget -O /usr/local/bin/quectel-CM http://leux.cn/dl/quectel-CM
	chmod 755 /usr/local/bin/quectel-CM

	# 配置脚本来开机自启
	cat << EOF > /etc/systemd/system/quectel-cm.service
[Unit]
Description=Quectel-CM Service
After=network.target
Wants=network.target

[Service]
ExecStop=/bin/kill -s TERM \$MAINPID
ExecStart=/usr/local/bin/quectel-CM -s ctnet -4 -6

[Install]
WantedBy=multi-user.target
EOF

	# 设置软件开机自启
	systemctl enable quectel-cm

} # InstallQuectel-CM

GetFirmwareMali() {
	# 获取MALI固件驱动
	wget -O /lib/firmware/mali_csffw.bin https://github.com/JeffyCN/mirrors/raw/ca33693a03b2782edc237d1d3b786f94849bed7d/firmware/g610/mali_csffw.bin

} # GetFirmwareMali

Main "$@"
