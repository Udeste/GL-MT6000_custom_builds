#!/bin/sh

# ---- Airtime Fairness ----
# Ensure airtime fairness + deficit mode both on (default, but explicit)
echo 3 > /sys/kernel/debug/ieee80211/phy0/airtime_flags
echo 3 > /sys/kernel/debug/ieee80211/phy1/airtime_flags

# ---- Verify settings applied ----
logger -t wifi-tune "Airtime fairness flags: $(cat /sys/kernel/debug/ieee80211/phy0/airtime_flags)"


