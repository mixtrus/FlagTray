#!/bin/bash
set -e

echo "Reverting IRQ affinity to all CPUs..."
for irq in $(cut -d: -f1 /proc/interrupts | tr -d ' '); do
  echo ffffffff > /proc/irq/$irq/smp_affinity || true
done

echo "Flushing all nftables rules..."
nft flush ruleset

echo "Resetting network-related sysctl settings to defaults..."
sysctl -w net.core.somaxconn=128
sysctl -w net.ipv4.tcp_max_syn_backlog=128
sysctl -w net.ipv4.tcp_timestamps=1
sysctl -w kernel.sysrq=438
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.ipv4.tcp_congestion_control=reno
sysctl -w net.ipv4.tcp_tw_reuse=0
sysctl -w net.ipv4.tcp_syncookies=1

echo "Restoring /etc/resolv.conf to use Google DNS..."
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
chattr -i /etc/resolv.conf || true

echo "Restarting networking service..."
systemctl restart networking || true

echo "All settings reverted. Rebooting now..."
reboot
