#!/bin/bash
# Ubuntu 24.04 LTS Server SSH Fix & System Optimization Script
# Modern approach with SSH connection protection and firewall management
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Create backup directory
BACKUP_DIR="/root/system_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

log ">>> [1/18] System Information & Backup Creation"
uname -a > "$BACKUP_DIR/system_info.txt"
lsb_release -a >> "$BACKUP_DIR/system_info.txt" 2>/dev/null || true
ip addr show > "$BACKUP_DIR/network_interfaces.txt"
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup" 2>/dev/null || true
systemctl list-unit-files --state=enabled > "$BACKUP_DIR/enabled_services.txt"

log ">>> [2/18] Update System Packages"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget net-tools unzip jq socat lsof htop iproute2 dnsutils \
  iputils-ping git gnupg2 ca-certificates build-essential haveged ethtool \
  pciutils sysstat cpufrequtils openssh-server fail2ban ufw iptables-persistent \
  netfilter-persistent > /dev/null 2>&1 || true

log ">>> [3/18] SSH Configuration Hardening & Connection Fix"
# Backup current SSH config
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.original" 2>/dev/null || true

# Modern SSH configuration for Ubuntu 24.04
cat > /etc/ssh/sshd_config << 'EOF'
# Ubuntu 24.04 Optimized SSH Configuration
Include /etc/ssh/sshd_config.d/*.conf

Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Ciphers and keying
RekeyLimit default none
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha2-256,hmac-sha2-512
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication
LoginGraceTime 2m
PermitRootLogin yes
StrictModes yes
MaxAuthTries 6
MaxSessions 10

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2

PasswordAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no

# Connection settings
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Performance optimizations
TCPKeepAlive yes
ClientAliveInterval 60
ClientAliveCountMax 3
Compression yes

# Security
AllowUsers *
DenyUsers
AllowGroups
DenyGroups
EOF

# Restart SSH service safely
log "Testing SSH configuration..."
sshd -t || (error "SSH config test failed! Restoring backup..." && cp "$BACKUP_DIR/sshd_config.original" /etc/ssh/sshd_config)
systemctl restart ssh
systemctl enable ssh

log ">>> [4/18] Disable ALL Firewalls (UFW & nftables)"
# Stop and disable UFW
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
ufw --force reset 2>/dev/null || true
ufw --force disable 2>/dev/null || true

# Stop and disable nftables
systemctl stop nftables 2>/dev/null || true
systemctl disable nftables 2>/dev/null || true
nft flush ruleset 2>/dev/null || true

# Clear iptables rules
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Clear ip6tables rules
ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true
ip6tables -P INPUT ACCEPT 2>/dev/null || true
ip6tables -P FORWARD ACCEPT 2>/dev/null || true
ip6tables -P OUTPUT ACCEPT 2>/dev/null || true

# Stop netfilter-persistent
systemctl stop netfilter-persistent 2>/dev/null || true
systemctl disable netfilter-persistent 2>/dev/null || true

warn "ALL FIREWALLS DISABLED - Server is now COMPLETELY OPEN!"

log ">>> [5/18] Network Stack Optimization (IPv6 Enabled)"
# Backup original sysctl settings
sysctl -a > "$BACKUP_DIR/sysctl_original.conf" 2>/dev/null || true

cat > /etc/sysctl.d/99-network-optimization.conf << 'EOF'
# IPv6 Configuration
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
net.ipv6.conf.all.autoconf = 1
net.ipv6.conf.default.autoconf = 1

# TCP Performance Tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 268435456
net.core.wmem_max = 268435456
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 65535
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_rmem = 4096 131072 268435456
net.ipv4.tcp_wmem = 4096 131072 268435456
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30

# Security
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

log ">>> [6/18] System Resource Limits"
cp /etc/security/limits.conf "$BACKUP_DIR/limits.conf.backup" 2>/dev/null || true

cat >> /etc/security/limits.conf << 'EOF'
# Custom limits for performance
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF

# Apply file descriptor limits immediately
ulimit -n 1048576

log ">>> [7/18] IRQ Affinity Tuning (SSH-Safe Mode)"
# Get SSH interface to avoid disconnection
ssh_nic=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || echo "unknown")
irq_index=0
cpu_count=$(nproc)

for nic in $(ls /sys/class/net | grep -v lo); do
  echo "Checking IRQs for $nic..."
  
  # Skip SSH interface to prevent disconnection
  if [[ "$nic" == "$ssh_nic" ]]; then
    warn "Skipping $nic (SSH interface) to prevent disconnection"
    continue
  fi
  
  # Get IRQ list for this interface
  irq_list=$(grep "$nic" /proc/interrupts 2>/dev/null | awk '{print $1}' | tr -d : || true)
  
  if [[ -n "$irq_list" ]]; then
    for irq in $irq_list; do
      if [[ -w "/proc/irq/$irq/smp_affinity" ]]; then
        core=$((irq_index % cpu_count))
        mask=$((1 << core))
        printf "%x" $mask > /proc/irq/$irq/smp_affinity 2>/dev/null || true
        echo "  IRQ $irq → CPU$core"
        irq_index=$((irq_index + 1))
      fi
    done
  fi
done

log ">>> [8/18] CPU Performance Governor"
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors ]]; then
  if grep -q 'performance' /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; then
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
    systemctl enable cpufrequtils 2>/dev/null || true
    
    # Set performance governor for all CPUs
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      [[ -w "$cpu" ]] && echo performance > "$cpu" 2>/dev/null || true
    done
    log "Performance governor enabled"
  else
    warn "Performance governor not available"
  fi
else
  warn "CPU frequency scaling not available"
fi

log ">>> [9/18] Network Interface Optimization"
for nic in $(ls /sys/class/net | grep -E '^(eth|ens|enp)'); do
  echo "Optimizing $nic..."
  
  # Enable hardware offloading features
  ethtool -K $nic gro on 2>/dev/null || true
  ethtool -K $nic lro on 2>/dev/null || true
  ethtool -K $nic tso on 2>/dev/null || true
  ethtool -K $nic gso on 2>/dev/null || true
  ethtool -K $nic rx-checksumming on 2>/dev/null || true
  ethtool -K $nic tx-checksumming on 2>/dev/null || true
  
  # Set ring buffer sizes (if supported)
  ethtool -G $nic rx 4096 tx 4096 2>/dev/null || true
  
  # Enable receive packet steering
  if [[ -f "/sys/class/net/$nic/queues/rx-0/rps_cpus" ]]; then
    echo $((2**$(nproc) - 1)) > "/sys/class/net/$nic/queues/rx-0/rps_cpus" 2>/dev/null || true
  fi
done

log ">>> [10/18] Modern DNS Configuration"
cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup" 2>/dev/null || true

# Use systemd-resolved for modern DNS management
systemctl enable systemd-resolved
systemctl start systemd-resolved

# Configure DNS servers
mkdir -p /etc/systemd/resolved.conf.d/
cat > /etc/systemd/resolved.conf.d/99-custom-dns.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
DNS=2606:4700:4700::1111 2606:4700:4700::1001 2001:4860:4860::8888 2001:4860:4860::8844
FallbackDNS=9.9.9.9 149.112.112.112
Domains=~.
DNSSEC=yes
DNSOverTLS=yes
Cache=yes
EOF

systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true

log ">>> [11/18] Systemd Journal Optimization"
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/99-optimization.conf << 'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=1month
MaxFileSec=1week
Compress=yes
Seal=yes
SplitMode=uid
RateLimitInterval=30s
RateLimitBurst=10000
EOF

systemctl restart systemd-journald

log ">>> [12/18] Memory Management Optimization"
cat > /etc/sysctl.d/99-memory-optimization.conf << 'EOF'
# Memory management
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 12000
vm.dirty_writeback_centisecs = 1500
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
vm.min_free_kbytes = 65536

# Transparent Huge Pages
vm.nr_hugepages = 0
EOF

# Disable Transparent Huge Pages
if [[ -d /sys/kernel/mm/transparent_hugepage ]]; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
  echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
  
  # Create service to disable THP on boot
  cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable disable-thp
fi

log ">>> [13/18] Kernel Scheduler Optimization"
cat > /etc/sysctl.d/99-scheduler-optimization.conf << 'EOF'
# Scheduler tuning
kernel.sched_migration_cost_ns = 5000000
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
kernel.sched_latency_ns = 24000000
kernel.sched_rr_timeslice_ms = 25
kernel.sched_rt_period_us = 1000000
kernel.sched_rt_runtime_us = 950000

# Process limits
kernel.pid_max = 4194304
kernel.threads-max = 4194304

# System responsiveness
kernel.sysrq = 1
kernel.panic = 10
EOF

log ">>> [14/18] I/O Scheduler Optimization"
# Set I/O schedulers for different device types
for device in $(lsblk -d -o NAME -n | grep -E '^(sd|nvme|vd)'); do
  if [[ -f "/sys/block/$device/queue/scheduler" ]]; then
    # Use mq-deadline for SSDs/NVMe, bfq for HDDs
    if [[ "$device" =~ ^nvme ]] || [[ $(cat /sys/block/$device/queue/rotational 2>/dev/null) == "0" ]]; then
      echo mq-deadline > "/sys/block/$device/queue/scheduler" 2>/dev/null || true
      echo "Set mq-deadline scheduler for $device (SSD/NVMe)"
    else
      echo bfq > "/sys/block/$device/queue/scheduler" 2>/dev/null || true
      echo "Set bfq scheduler for $device (HDD)"
    fi
    
    # Optimize queue depth
    echo 32 > "/sys/block/$device/queue/nr_requests" 2>/dev/null || true
  fi
done

log ">>> [15/18] Power Management Optimization"
# Disable power management features that can cause latency
if [[ -d /sys/devices/system/cpu/cpuidle ]]; then
  for state in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    [[ -f "$state" ]] && echo 1 > "$state" 2>/dev/null || true
  done
fi

# Disable system sleep/suspend
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

log ">>> [16/18] Security Services Management"
# Configure fail2ban but don't block SSH
cp /etc/fail2ban/jail.conf "$BACKUP_DIR/jail.conf.backup" 2>/dev/null || true

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 10
backend = systemd

[sshd]
enabled = false
EOF

systemctl enable fail2ban
systemctl restart fail2ban

log ">>> [17/18] Apply All System Changes"
# Apply sysctl changes
sysctl --system > /dev/null

# Update initramfs
update-initramfs -u -k all > /dev/null 2>&1 || true

# Generate SSH host keys if missing
ssh-keygen -A > /dev/null 2>&1 || true

log ">>> [18/18] Final System Status Check"
echo ""
echo "=== SYSTEM OPTIMIZATION SUMMARY ==="
echo "- SSH Service: $(systemctl is-active ssh)"
echo "- UFW Firewall: $(systemctl is-active ufw 2>/dev/null || echo 'disabled')"
echo "- nftables: $(systemctl is-active nftables 2>/dev/null || echo 'disabled')"
echo "- DNS Resolver: $(systemctl is-active systemd-resolved)"
echo "- CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'not available')"
echo "- TCP Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
echo "- Open File Limit: $(ulimit -n)"
echo "- Backup Location: $BACKUP_DIR"
echo ""

warn "⚠️  IMPORTANT SECURITY NOTICE ⚠️"
warn "ALL FIREWALLS HAVE BEEN DISABLED!"
warn "Your server is completely open to the internet!"
warn "Consider re-enabling appropriate firewall rules after testing."

log "✅ System optimization completed successfully!"
log "📁 Backup files saved to: $BACKUP_DIR"

echo ""
read -p "🔄 Reboot now to apply all kernel changes? [y/N]: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "🔄 Rebooting system..."
    sleep 3
    reboot
else
    warn "Manual reboot recommended to apply all changes"
fi
