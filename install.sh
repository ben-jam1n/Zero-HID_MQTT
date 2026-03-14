#!/bin/bash
# install.sh - Install Zero-HID_MQTT on Linux
# https://github.com/ben-jam1n/Zero-HID_MQTT
# This script automates setup on Linux systems (Raspberry Pi, Debian, Ubuntu, etc.)
# Requires: sudo access

set -e

# 1. Install system dependencies
echo "Step 1: Installing system dependencies..."
# sudo apt-get update
# sudo apt-get install -y python3 python3-venv python3-pip git


# 2 Install USB Gadget Module (if on Raspberry Pi)
echo "Step 2: Installing zero-hid USB Gadget module..."
Zero_HID_DIR="/opt/Zero-HID"
Zero_HID_GITHUB_URL="https://github.com/thewh1teagle/zero-hid"

# 2.1 Create install directory
echo "Creating zero-hid installation directory..."
sudo mkdir -p "$Zero_HID_DIR"
sudo chown $USER:$USER "$Zero_HID_DIR"

# 2.2. Clone repository
echo "Cloning repository..."
if [ -d "$Zero_HID_DIR/.git" ]; then
    echo "Repository already exists, pulling latest changes..."
    cd "$Zero_HID_DIR" && git pull
else
    git clone "$Zero_HID_GITHUB_URL" "$Zero_HID_DIR"
fi

# 2.3 Install zero-hid usb_gadget module
echo "Installing zero-hid USB Gadget module..."
cd $Zero_HID_DIR && cd ./usb_gadget
sudo ./installer
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install zero-hid USB Gadget module!"
    exit 1
fi

# 2.4 Remove conflicting g_ether from kernel command line (if present)
echo "Checking for g_ether conflicts in boot configuration..."
CMDLINE_FILE=""
if [ -f "/boot/firmware/cmdline.txt" ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f "/boot/cmdline.txt" ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
    if grep -q "g_ether" "$CMDLINE_FILE"; then
        echo "Found g_ether in kernel command line - removing to prevent UDC conflicts..."
        sudo sed -i 's/modules-load=dwc2,g_ether/modules-load=dwc2/g' "$CMDLINE_FILE"
        echo "  ✓ Removed g_ether from $CMDLINE_FILE"
    else
        echo "  ✓ No g_ether conflict found"
    fi
fi

# 2.5 Verify HID gadget devices exist
echo "Verifying HID gadget devices..."
RETRY_COUNT=0
MAX_RETRIES=5
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -c "/dev/hidg0" ] && [ -c "/dev/hidg1" ] && [ -c "/dev/hidg2" ]; then
        echo "  ✓ HID gadget devices created successfully"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "  Waiting for HID devices to appear (attempt $RETRY_COUNT/$MAX_RETRIES)..."
        sleep 2
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "WARNING: HID gadget devices did not appear. This may cause issues."
    echo "Please verify:"
    echo "  1. USB cable is a data cable, not power-only"
    echo "  2. dtoverlay=dwc2 is set in /boot/firmware/config.txt or /boot/config.txt"
    echo "  3. Run: sudo $Zero_HID_DIR/usb_gadget/troubleshoot.sh (if available)"
fi

echo "zero-hid USB Gadget module installation complete!"
echo "Now installing Zero-HID_MQTT service..."

INSTALL_DIR="/opt/Zero-HID_MQTT"
SERVICE_FILE="/etc/systemd/system/Zero-HID_MQTT.service"
GITHUB_URL="https://github.com/ben-jam1n/Zero-HID_MQTT.git"



# 3 Create install directory
echo "Step 3: Installing Zero-HID_MQTT..."
echo "Creating installation directory..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

# 3.1 Clone repository
echo "Cloning repository..."
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Repository already exists, pulling latest changes..."
    cd "$INSTALL_DIR" && git pull
else
    git clone "$GITHUB_URL" "$INSTALL_DIR"
fi

# 3.2 Create and activate Python virtual environment
echo "Creating Python virtual environment..."
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"

# 3.3 Install required Python packages in venv
echo "Installing Python dependencies..."
pip install --upgrade pip setuptools wheel
pip install -r "$INSTALL_DIR/requirements.txt"
deactivate

# 3.4 Set script permissions
echo "Setting permissions..."
chmod +x "$INSTALL_DIR/Zero-HID_MQTT.py"

# 3.5 Create systemd service file
echo "Creating systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Zero-HID_MQTT https://github.com/ben-jam1n/Zero-HID_MQTT
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/Zero-HID_MQTT.py $INSTALL_DIR/config.yaml
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 3.6 Enable and start the service
echo "Enabling and starting systemd services..."
sudo systemctl daemon-reload
sudo systemctl enable Zero-HID_MQTT.service

# 3.7 Verify installation
echo ""
echo "Verifying installation..."
sleep 2

if ! sudo systemctl is-enabled Zero-HID_MQTT.service > /dev/null 2>&1; then
    echo "ERROR: Failed to enable Zero-HID_MQTT service!"
    exit 1
fi
echo "  ✓ Zero-HID_MQTT service enabled"

if ! grep -q "^MQTT_BROKER" "$INSTALL_DIR/config.yaml" 2>/dev/null; then
    echo "  ⚠ WARNING: config.yaml not properly configured"
    echo "    Please copy example_config.yaml to config.yaml and update it"
fi


# Final instructions
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Copy and edit the configuration file:"
echo "   cp $INSTALL_DIR/example_config.yaml $INSTALL_DIR/config.yaml"
echo "   sudo nano $INSTALL_DIR/config.yaml"
echo "2. Update MQTT broker settings and controls"
echo "3. Start the service:"
echo "   sudo systemctl start Zero-HID_MQTT.service"
echo "4. Check service status:"
echo "   sudo systemctl status Zero-HID_MQTT.service"
echo "5. View logs in real-time:"
echo "   sudo journalctl -u Zero-HID_MQTT.service -f"
echo ""
echo "Troubleshooting:"
echo "If you're having issues, run the diagnostic script:"
echo "   bash $INSTALL_DIR/troubleshoot.sh"
echo ""
echo "For more information, see README.md on https://github.com/ben-jam1n/Zero-HID_MQTT"
echo "=========================================="
