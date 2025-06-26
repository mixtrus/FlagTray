cat <<'EOF' > fix_ssh.sh
#!/bin/bash
set -e
echo "Reset IRQ affinity"
for irq in $(cut -d: -f1 /proc/interrupts | tr -d ' '); do
  echo ffffffff > /proc/irq/$irq/smp_affinity || true
done
echo "Flush and reset nftables"
nft flush ruleset
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; }
nft add chain inet filter forward { type filter hook forward priority 0 \; }
nft add chain inet filter output { type filter hook output priority 0 \; }
nft add rule inet filter input accept
nft add rule inet filter forward accept
nft add rule inet filter output accept
echo "Reset network sysctl"
sysctl -w net.core.somaxconn=128
sysctl -w net.ipv4.tcp_max_syn_backlog=128
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.ipv4.tcp_congestion_control=reno
sysctl -w net.ipv4.tcp_tw_reuse=0
echo "Reset DNS resolver"
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" > /etc/resolv.conf
chattr -i /etc/resolv.conf || true
echo "Restart networking"
systemctl restart networking || true
ip addr flush dev "$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')" && dhclient -v
echo "Done! Try reconnecting via SSH."
EOF
chmod +x fix_ssh.sh
