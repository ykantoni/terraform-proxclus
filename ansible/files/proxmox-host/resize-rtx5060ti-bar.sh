#!/bin/bash
set -e

GPU="0000:01:00.0"
DEV="/sys/bus/pci/devices/$GPU"

if [ -e "/sys/bus/pci/drivers/vfio-pci/$GPU" ]; then
    echo "$GPU" > /sys/bus/pci/drivers/vfio-pci/unbind
fi

echo 7 > "$DEV/resource1_resize"

echo "$GPU" > /sys/bus/pci/drivers/vfio-pci/bind

