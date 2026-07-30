#!/bin/sh

# Restore TX power on 2.4Ghz
uci del wireless.radio0.txpower

# Enable 5Ghz
uci set wireless.radio1.disabled=0
uci set wireless.default_radio1.disabled=0
uci commit wireless
wifi reload
