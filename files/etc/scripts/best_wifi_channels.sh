#!/bin/sh
# best_channel.sh
# Automatically finds and sets the best 2.4GHz WiFi channel (1, 6, or 11)
# Usage: best_channel.sh [--dry-run] [interface]
# Cron: 0 4 * * * /root/best_channel.sh 2>&1 | logger -t best_channel

set -e

# Configuration
DRY_RUN=0
IFACE=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run|-d)
            DRY_RUN=1
            ;;
        *)
            IFACE="$arg"
            ;;
    esac
done

# Auto-detect 2.4GHz interface if not specified
if [ -z "$IFACE" ]; then
    echo "Auto-detecting 2.4GHz interface..."
    for radio in /sys/class/ieee80211/*/device/net/*; do
        if [ -d "$radio" ]; then
            iface=$(basename "$radio")
            # Check if it's 2.4GHz by looking at available channels
            if iwinfo "$iface" freqlist 2>/dev/null | grep -q "2\.4[0-9][0-9] GHz"; then
                IFACE="$iface"
                echo "Found 2.4GHz interface: $IFACE"
                break
            fi
        fi
    done

    if [ -z "$IFACE" ]; then
        echo "Error: No 2.4GHz interface found" >&2
        exit 1
    fi
fi

# Validate interface exists
if ! iwinfo "$IFACE" info >/dev/null 2>&1; then
    echo "Error: Interface $IFACE not found or not wireless" >&2
    exit 1
fi

# Find the radio device (radio0, radio1, etc)
RADIO=""
for radio_name in radio0 radio1 radio2 radio3; do
    radio_iface=$(uci get wireless.${radio_name}.device 2>/dev/null || echo "")
    if [ -n "$radio_iface" ]; then
        # Check if this radio's interface matches
        radio_mode=$(uci get wireless.default_${radio_name}.mode 2>/dev/null || echo "ap")
        if [ "$radio_mode" = "ap" ]; then
            test_iface=$(uci get wireless.default_${radio_name}.ifname 2>/dev/null || echo "${radio_name}-ap0")
            if echo "$IFACE" | grep -q "$radio_name"; then
                RADIO="$radio_name"
                break
            fi
        fi
    fi
done

if [ -z "$RADIO" ]; then
    # Fallback: assume radio0 for 2.4GHz
    RADIO="radio0"
    echo "Warning: Could not determine radio name, assuming $RADIO"
fi

echo "==================================================================="
echo "WiFi Channel Optimizer - 2.4GHz"
echo "==================================================================="
echo "Interface: $IFACE"
echo "Radio: wireless.$RADIO"
echo ""

# Perform scan
echo "Scanning nearby networks..."
SCAN=$(iwinfo "$IFACE" scan 2>/dev/null)

if [ -z "$SCAN" ]; then
    echo "Error: WiFi scan failed on $IFACE" >&2
    exit 1
fi

# Parse scan results - proper variable handling without subshell
SCAN_DATA=$(echo "$SCAN" | awk '
/Channel:/ { ch=$NF }
/Signal:/ {
    gsub(/ dBm/, "", $2)
    sig=$2
    if (ch != "" && sig != "") {
        print ch, sig
    }
    ch = ""
    sig = ""
}
')

# Initialize counters
ch1_count=0
ch1_strongest=-100
ch6_count=0
ch6_strongest=-100
ch11_count=0
ch11_strongest=-100

# Process each AP
echo "$SCAN_DATA" | while read channel signal; do
    [ -z "$channel" ] && continue

    # Channel 1 group (channels 1-4)
    if [ "$channel" -ge 1 ] && [ "$channel" -le 4 ]; then
        ch1_count=$((ch1_count + 1))
        if [ "$signal" -gt "$ch1_strongest" ]; then
            ch1_strongest=$signal
        fi
    fi

    # Channel 6 group (channels 3-9)
    if [ "$channel" -ge 3 ] && [ "$channel" -le 9 ]; then
        ch6_count=$((ch6_count + 1))
        if [ "$signal" -gt "$ch6_strongest" ]; then
            ch6_strongest=$signal
        fi
    fi

    # Channel 11 group (channels 8-13)
    if [ "$channel" -ge 8 ] && [ "$channel" -le 13 ]; then
        ch11_count=$((ch11_count + 1))
        if [ "$signal" -gt "$ch11_strongest" ]; then
            ch11_strongest=$signal
        fi
    fi

    # Store in temp variables (will be read after loop)
    echo "$ch1_count $ch1_strongest $ch6_count $ch6_strongest $ch11_count $ch11_strongest" > /tmp/channel_data.tmp
done

# Read final counts from temp file
if [ -f /tmp/channel_data.tmp ]; then
    read ch1_count ch1_strongest ch6_count ch6_strongest ch11_count ch11_strongest < /tmp/channel_data.tmp
    rm -f /tmp/channel_data.tmp
fi

# Set defaults if no data
ch1_count=${ch1_count:-0}
ch1_strongest=${ch1_strongest:--100}
ch6_count=${ch6_count:-0}
ch6_strongest=${ch6_strongest:--100}
ch11_count=${ch11_count:-0}
ch11_strongest=${ch11_strongest:--100}

# Calculate scores (lower is better)
# Formula: (AP count × 5) + (signal strength penalty)
score_ch1=$((ch1_count * 5 + (100 + ch1_strongest)))
score_ch6=$((ch6_count * 5 + (100 + ch6_strongest)))
score_ch11=$((ch11_count * 5 + (100 + ch11_strongest)))

echo "Channel Analysis:"
echo "-------------------------------------------------------------------"
printf "%-10s | %-8s | %-15s | %-10s\n" "Channel" "APs" "Strongest (dBm)" "Score"
echo "-------------------------------------------------------------------"
printf "%-10s | %-8d | %-15d | %-10d\n" "Ch 1" "$ch1_count" "$ch1_strongest" "$score_ch1"
printf "%-10s | %-8d | %-15d | %-10d\n" "Ch 6" "$ch6_count" "$ch6_strongest" "$score_ch6"
printf "%-10s | %-8d | %-15d | %-10d\n" "Ch 11" "$ch11_count" "$ch11_strongest" "$score_ch11"
echo "-------------------------------------------------------------------"
echo ""

# Determine best channel
best_channel=6
best_score=$score_ch6

if [ "$score_ch1" -lt "$best_score" ]; then
    best_channel=1
    best_score=$score_ch1
fi

if [ "$score_ch11" -lt "$best_score" ]; then
    best_channel=11
    best_score=$score_ch11
fi

# Get current channel
CURRENT=$(uci get wireless.${RADIO}.channel 2>/dev/null || echo "auto")

echo "Current Channel: $CURRENT"
echo "Recommended Channel: $best_channel (score: $best_score)"
echo ""

# Apply changes
if [ "$CURRENT" = "$best_channel" ]; then
    echo "✓ Already on the optimal channel. No changes needed."
    exit 0
fi

if [ $DRY_RUN -eq 1 ]; then
    echo "[DRY RUN] Would switch to channel $best_channel"
    echo "[DRY RUN] Command: uci set wireless.${RADIO}.channel=$best_channel"
    echo "[DRY RUN] No changes made."
    exit 0
fi

echo "Switching to channel $best_channel..."
uci set wireless.${RADIO}.channel="$best_channel"
uci commit wireless

echo "Reloading WiFi..."
wifi reload

echo "✓ Successfully switched to channel $best_channel"
echo ""
echo "Note: WiFi reload may take 10-30 seconds to complete."


