#!/bin/bash
# troubleshoot.sh - Diagnostic script for Zero-HID_MQTT
# https://github.com/ben-jam1n/Zero-HID_MQTT
#
# This script helps diagnose common issues with Zero-HID_MQTT installation

set +e  # Don't exit on errors - we want to gather all diagnostics

echo "=========================================="
echo "Zero-HID_MQTT Diagnostic Tool"
echo "=========================================="
echo ""

FAILED=0
WARNINGS=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

echo "=== Checking USB Gadget Setup ==="
echo ""

# Check if HID devices exist
if [ -c /dev/hidg0 ] && [ -c /dev/hidg1 ] && [ -c /dev/hidg2 ]; then
    pass "HID gadget devices exist (/dev/hidg0, /dev/hidg1, /dev/hidg2)"
else
    fail "HID gadget devices not found. Run: sudo systemctl restart usb_gadget.service"
fi

# Check if dwc2 module is loaded
if lsmod | grep -q "dwc2"; then
    pass "dwc2 USB controller module loaded"
else
    fail "dwc2 module not loaded. Check /etc/modules"
fi

# Check if libcomposite is loaded
if lsmod | grep -q "libcomposite"; then
    pass "libcomposite module loaded"
else
    warn "libcomposite module not loaded (should load automatically)"
fi

# Check UDC state
if [ -f /sys/class/udc/3f980000.usb/state ]; then
    STATE=$(cat /sys/class/udc/3f980000.usb/state)
    if [ "$STATE" = "attached" ]; then
        pass "USB Device Controller (UDC) attached to host"
    else
        fail "UDC not attached to host. State: $STATE"
        echo "  This means the Pi isn't properly enumerated as a USB device."
        echo "  Check: USB cable quality, connection port, and kernel logs"
    fi
else
    warn "UDC state file not found"
fi

# Check for g_ether conflict
if [ -f /boot/firmware/cmdline.txt ]; then
    if grep -q "g_ether" /boot/firmware/cmdline.txt; then
        fail "g_ether found in /boot/firmware/cmdline.txt - causes UDC conflicts!"
        echo "  Fix: sudo sed -i 's/modules-load=dwc2,g_ether/modules-load=dwc2/g' /boot/firmware/cmdline.txt"
        echo "  Then reboot: sudo reboot"
    else
        pass "No g_ether conflict in /boot/firmware/cmdline.txt"
    fi
elif [ -f /boot/cmdline.txt ]; then
    if grep -q "g_ether" /boot/cmdline.txt; then
        fail "g_ether found in /boot/cmdline.txt - causes UDC conflicts!"
        echo "  Fix: sudo sed -i 's/modules-load=dwc2,g_ether/modules-load=dwc2/g' /boot/cmdline.txt"
        echo "  Then reboot: sudo reboot"
    else
        pass "No g_ether conflict in /boot/cmdline.txt"
    fi
else
    warn "Cannot find kernel command line file"
fi

# Check dtoverlay configuration
if [ -f /boot/firmware/config.txt ]; then
    if grep -q "dtoverlay=dwc2" /boot/firmware/config.txt; then
        pass "dwc2 device tree overlay enabled in /boot/firmware/config.txt"
    else
        fail "dwc2 overlay not found in /boot/firmware/config.txt"
        echo "  Add: dtoverlay=dwc2 to /boot/firmware/config.txt and reboot"
    fi
elif [ -f /boot/config.txt ]; then
    if grep -q "dtoverlay=dwc2" /boot/config.txt; then
        pass "dwc2 device tree overlay enabled in /boot/config.txt"
    else
        fail "dwc2 overlay not found in /boot/config.txt"
        echo "  Add: dtoverlay=dwc2 to /boot/config.txt and reboot"
    fi
else
    warn "Cannot find boot config file"
fi

echo ""
echo "=== Checking Zero-HID_MQTT Service ==="
echo ""

# Check if service is enabled
if systemctl is-enabled Zero-HID_MQTT.service > /dev/null 2>&1; then
    pass "Zero-HID_MQTT service is enabled"
else
    fail "Zero-HID_MQTT service not enabled"
    echo "  Fix: sudo systemctl enable Zero-HID_MQTT.service"
fi

# Check if service is running
if systemctl is-active Zero-HID_MQTT.service > /dev/null 2>&1; then
    pass "Zero-HID_MQTT service is running"
else
    fail "Zero-HID_MQTT service not running"
    echo "  Fix: sudo systemctl start Zero-HID_MQTT.service"
fi

# Check config file exists
if [ -f /opt/Zero-HID_MQTT/config.yaml ]; then
    pass "Configuration file found: /opt/Zero-HID_MQTT/config.yaml"
    
    # Check if broker is configured
    if grep -q "mqtt_broker:" /opt/Zero-HID_MQTT/config.yaml; then
        BROKER=$(grep "mqtt_broker:" /opt/Zero-HID_MQTT/config.yaml | head -1 | cut -d' ' -f2)
        if [ "$BROKER" != "xxx.xxx.xxx.xxx" ] && [ -n "$BROKER" ]; then
            pass "MQTT broker configured: $BROKER"
        else
            warn "MQTT broker not properly configured in config.yaml"
        fi
    fi
else
    fail "Configuration file not found: /opt/Zero-HID_MQTT/config.yaml"
    echo "  Fix: cp /opt/Zero-HID_MQTT/example_config.yaml /opt/Zero-HID_MQTT/config.yaml"
    echo "  Then: sudo nano /opt/Zero-HID_MQTT/config.yaml"
fi

echo ""
echo "=== Checking MQTT Connectivity ==="
echo ""

# Try to get MQTT broker from config
if [ -f /opt/Zero-HID_MQTT/config.yaml ]; then
    MQTT_BROKER=$(grep "mqtt_broker:" /opt/Zero-HID_MQTT/config.yaml | head -1 | awk '{print $2}')
    if [ -n "$MQTT_BROKER" ] && [ "$MQTT_BROKER" != "xxx.xxx.xxx.xxx" ]; then
        if command -v nc &> /dev/null; then
            if nc -z -w 2 "$MQTT_BROKER" 1883 2>/dev/null; then
                pass "MQTT broker is reachable at $MQTT_BROKER:1883"
            else
                warn "Cannot reach MQTT broker at $MQTT_BROKER:1883"
                echo "  Check: Broker IP/hostname and network connectivity"
            fi
        else
            warn "netcat not available for connectivity test"
        fi
    fi
fi

echo ""
echo "=== Recent Service Logs ==="
echo ""
echo "Last 20 lines of Zero-HID_MQTT service log:"
journalctl -u Zero-HID_MQTT.service -n 20 --no-pager || echo "(Cannot read journal)"

echo ""
echo "=== Kernel Messages Related to USB/Gadget ==="
echo ""
echo "Recent USB/gadget related kernel messages:"
dmesg | grep -i "gadget\|dwc\|usb.*device" | tail -10 || echo "(No messages found)"

echo ""
echo "=========================================="
echo "Diagnostic Summary:"
echo "=========================================="
echo -e "Issues Found: ${RED}$FAILED${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo "If you're still having issues, check:"
    echo "  1. USB cable quality (try a different cable)"
    echo "  2. Direct USB connection to computer (not through hub)"
    echo "  3. MQTT message format in Home Assistant"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}Some warnings detected. Check the details above.${NC}"
    exit 0
else
    echo -e "${RED}Issues detected. Fix them and try again.${NC}"
    echo "For more help, see:"
    echo "  https://github.com/ben-jam1n/Zero-HID_MQTT/blob/main/README.md#troubleshooting"
    exit 1
fi
