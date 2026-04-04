#!/bin/sh

# Firewall rules to enable
ENABLE_RULES() {
    ssh root@router '
    uci set firewall.@rule[9].enabled=1
    uci set firewall.@rule[10].enabled=1
    uci set firewall.@rule[11].enabled=1
    uci commit firewall
    service firewall restart
    '
}

# Firewall rules to disable (remove temporary rules)
DISABLE_RULES() {
    ssh root@router '
    uci set firewall.@rule[9].enabled=0
    uci set firewall.@rule[10].enabled=0
    uci set firewall.@rule[11].enabled=0
    uci commit firewall
    service firewall restart
    '
    exit 0
}

# Trap Ctrl+C and disable rules
trap DISABLE_RULES INT

# Enable rules
ENABLE_RULES

echo "Firewall rules enabled. Press Ctrl+C to disable."
while true; do sleep 1; done
