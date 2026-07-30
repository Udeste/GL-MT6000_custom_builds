#!/bin/sh

# Pin Ethernet (IRQ 120 = eth0 LAN) to CPU0
echo 1 > /proc/irq/120/smp_affinity
echo e > /sys/class/net/eth0/queues/rx-0/rps_cpus
echo e > /sys/class/net/br-lan/queues/rx-0/rps_cpus
for i in /sys/class/net/eth0/queues/tx-*/xps_cpus; do echo e > "$i"; done

# Pin WAN (IRQ 121 = eth1) to Cores 1+2
echo 6 > /proc/irq/121/smp_affinity
echo e > /sys/class/net/eth1/queues/rx-0/rps_cpus
for i in /sys/class/net/eth1/queues/tx-*/xps_cpus; do echo e > "$i"; done

# Pin Wi-Fi (IRQ 133 = mt7915e) to Core 3
echo 8 > /proc/irq/133/smp_affinity
for iface in phy0-ap0 phy1-ap0; do
    [ -d "/sys/class/net/$iface" ] && echo e > /sys/class/net/$iface/queues/rx-0/rps_cpus
done

# Bigger packet budget for 100Hz timer
echo 1000 > /proc/sys/net/core/netdev_budget
echo 5000 > /proc/sys/net/core/netdev_max_backlog
