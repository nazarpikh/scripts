#!/usr/bin/env bash

# ==============================================================================
# Script: Laptop-to-Server Optimization Setup
# Description: Automates Linux configuration to adapt a laptop for 24/7 server
#              operations. Disables sleep/suspend behaviors, configures Wi-Fi
#              power-saving options, sets up graceful UPower shutdown on low
#              battery, applies kernel panic watchdog parameters, tunes swap
#              usage, and caps systemd journal log sizes.
# ==============================================================================

set -u

# Ensure the script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "WARNING: This script must be run with root privileges (e.g., using sudo)."
  exit 1
fi

# Helper functions for formatted status output
log_success() {
    echo -e "[OK] $1"
}

log_warning() {
    echo -e "WARNING: $1"
}

echo "Starting Laptop Server Optimization setup..."
echo "--------------------------------------------------"

# ==============================================================================
# 1. Disable Sleep Mode on Lid Close
# ==============================================================================
echo "Configuring logind lid switch actions..."

LOGIND_CONF="/etc/systemd/logind.conf"
if [ -f "$LOGIND_CONF" ]; then
    # Update or append logind configurations
    sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
    sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$LOGIND_CONF"
    sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$LOGIND_CONF"

    if systemctl restart systemd-logind; then
        log_success "Lid switch ignore configuration applied and systemd-logind restarted successfully."
    else
        log_warning "Failed to restart systemd-logind service."
    fi
else
    log_warning "File $LOGIND_CONF not found. Skipping lid switch setup."
fi

# ==============================================================================
# 2. Disable Wi-Fi Power Saving in NetworkManager
# ==============================================================================
echo "Configuring NetworkManager Wi-Fi power saving..."

NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_WIFI_CONF="$NM_CONF_DIR/default-wifi-powersave-on.conf"

mkdir -p "$NM_CONF_DIR"

cat << 'EOF' > "$NM_WIFI_CONF"
[connection]
wifi.powersave = 2
EOF

if [ -f "$NM_WIFI_CONF" ]; then
    if systemctl restart NetworkManager; then
        log_success "NetworkManager Wi-Fi power saving disabled (wifi.powersave = 2)."
    else
        log_warning "NetworkManager configuration created, but failed to restart NetworkManager service."
    fi
else
    log_warning "Failed to create NetworkManager power-saving configuration file."
fi

# ==============================================================================
# 3. Disable Kernel-Level Power Saving for Wi-Fi Drivers
# ==============================================================================
echo "Detecting Wi-Fi chipset and configuring module power management..."

MODPROBE_DIR="/etc/modprobe.d"
mkdir -p "$MODPROBE_DIR"

UPDATE_INITRAMFS_NEEDED=false

if lspci -nnk | grep -i net | grep -iq "Intel"; then
    echo "Intel network adapter detected."
    echo "options iwlwifi power_save=0" > "$MODPROBE_DIR/iwlwifi.conf"
    if [ -f "$MODPROBE_DIR/iwlwifi.conf" ]; then
        log_success "Configured Intel iwlwifi driver power saving disabled."
        UPDATE_INITRAMFS_NEEDED=true
    else
        log_warning "Failed to create $MODPROBE_DIR/iwlwifi.conf."
    fi
elif lspci -nnk | grep -i net | grep -iq "Realtek"; then
    echo "Realtek network adapter detected."
    cat << 'EOF' > "$MODPROBE_DIR/rtl_powersave.conf"
options rtw88_core disable_lps_deep=y
options rtw88_pci disable_aspm=y
EOF
    if [ -f "$MODPROBE_DIR/rtl_powersave.conf" ]; then
        log_success "Configured Realtek rtw88 driver power saving disabled."
        UPDATE_INITRAMFS_NEEDED=true
    else
        log_warning "Failed to create $MODPROBE_DIR/rtl_powersave.conf."
    fi
else
    log_warning "No Intel or Realtek Wi-Fi adapter explicitly matched or no wireless chipset found via lspci."
fi

if [ "$UPDATE_INITRAMFS_NEEDED" = true ]; then
    echo "Updating initramfs..."
    if update-initramfs -u; then
        log_success "initramfs updated successfully."
    else
        log_warning "Failed to update initramfs."
    fi
fi

# ==============================================================================
# 4. Mask ACPI / systemd Sleep and Suspend Targets
# ==============================================================================
echo "Masking systemd sleep, suspend, and hibernate targets..."

if systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target > /dev/null 2>&1; then
    log_success "Sleep, suspend, hibernate, and hybrid-sleep targets masked successfully."
else
    log_warning "Failed to mask one or more systemd sleep targets."
fi

# ==============================================================================
# 5. Configure UPower Graceful Auto-Shutdown Thresholds
# ==============================================================================
echo "Configuring UPower automatic shutdown parameters..."

UPOWER_CONF="/etc/UPower/UPower.conf"

if [ -f "$UPOWER_CONF" ]; then
    sed -i 's/^#\?UsePercentageForPolicy=.*/UsePercentageForPolicy=true/' "$UPOWER_CONF"
    sed -i 's/^#\?PercentageLow=.*/PercentageLow=25/' "$UPOWER_CONF"
    sed -i 's/^#\?PercentageCritical=.*/PercentageCritical=20/' "$UPOWER_CONF"
    sed -i 's/^#\?PercentageAction=.*/PercentageAction=15/' "$UPOWER_CONF"
    sed -i 's/^#\?CriticalPowerAction=.*/CriticalPowerAction=PowerOff/' "$UPOWER_CONF"

    if systemctl restart upower; then
        log_success "UPower settings updated (Action threshold at 15%) and upower service restarted."
    else
        log_warning "UPower configuration updated, but failed to restart upower service."
    fi
else
    log_warning "UPower configuration file $UPOWER_CONF not found."
fi

# ==============================================================================
# 6 & 7. Apply Kernel Panic Watchdog & Tune Swappiness
# ==============================================================================
echo "Applying Kernel Panic Watchdog settings and tuning VM swappiness..."

SYSCTL_CONF="/etc/sysctl.d/99-server-reliability.conf"

cat << 'EOF' > "$SYSCTL_CONF"
# Automatic reboot 10 seconds after Kernel Panic
kernel.panic = 10
# Do not trigger reboot on Out-Of-Memory (OOM)
vm.panic_on_oom = 0

# Reduce Swap usage (activated only when 90% RAM usage is reached)
vm.swappiness = 10
EOF

if [ -f "$SYSCTL_CONF" ]; then
    if sysctl --system > /dev/null 2>&1; then
        log_success "Kernel Panic watchdog and swappiness parameters applied via $SYSCTL_CONF."
    else
        log_warning "Created $SYSCTL_CONF, but failed to apply sysctl parameters."
    fi
else
    log_warning "Failed to write sysctl parameters to $SYSCTL_CONF."
fi

# ==============================================================================
# 8. Limit Systemd Journal Log Size (Restricted to 500MB)
# ==============================================================================
echo "Configuring systemd-journald log rotation limits..."

JOURNAL_CONF="/etc/systemd/journald.conf"

if [ -f "$JOURNAL_CONF" ]; then
    sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' "$JOURNAL_CONF"

    if systemctl restart systemd-journald; then
        log_success "Systemd journal log size restricted to 500M and systemd-journald restarted."
    else
        log_warning "Journal configuration modified, but failed to restart systemd-journald service."
    fi
else
    log_warning "Systemd journal configuration file $JOURNAL_CONF not found."
fi

echo "--------------------------------------------------"
echo "Laptop Server Optimization script execution complete."
