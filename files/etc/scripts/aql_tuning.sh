#!/bin/sh


# ---- AQL Tuning ----
# Low limit: how aggressive the driver starts pushing back (latency control)
# High limit: hard ceiling before the queue is fully blocked
#
# Presets (WED off):
#   Low latency (gaming/VoIP):  low=1500  high=3000
#   Balanced (general use):     low=2500  high=5000
#   Max bandwidth (transfers):  low=8000  high=15000

aql_limit_low=2500
aql_limit_high=5000

for ac in 0 1 2 3; do
    echo $ac $aql_limit_low $aql_limit_high > /sys/kernel/debug/ieee80211/phy0/aql_txq_limit
    echo $ac $aql_limit_low $aql_limit_high > /sys/kernel/debug/ieee80211/phy1/aql_txq_limit
done

# Verify
logger -t wifi-tune "AQL limits set: low=$aql_limit_low high=$aql_limit_high"
