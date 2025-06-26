#!/bin/bash
set -e

echo "1. Reset IRQ affinity to all CPUs"
for irq in $(cut -d: -f1 /proc/interrupts | tr -d ' '); do
  echo ffffffff > /proc/irq/$irq/smp_affinity || true
done

echo "2. Flush nftables firewall rules (allow all)"
nft flush ruleset
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0\; }
nft add chain inet filter forward { type filter hook forward priority 0\; }
nft add chain inet filter output { type filter hook output priority 0\; }
nft add rule inet filter input accept
nft add rule inet filter forward accept
nft add rule inet filter output accept

echo "3. Reset sysctl network settings"
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.core.somaxconn=128
sysctl -w net.ipv4.tcp_max_syn_backlog=128
sysctl -w net.ipv4.tcp_congestion_control=reno
sysctl -w net.ipv4.tcp_tw_reuse=0
sysctl -w net.ipv4.tcp_syncookies=1
sysctl -w net.ipv4.tcp_timestamps=1

echo "4. Restore /etc/resolv.conf to Google DNS"
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
chattr -i /etc/resolv.conf || true

echo "5. Ensure SSH service is enabled and started"
systemctl enable ssh || true
systemctl restart ssh

echo "6. Restart networking"
systemctl restart networking || true

echo "Done! Rebooting system to apply cleanly..."
reboot
