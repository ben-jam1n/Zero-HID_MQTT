#!/bin/bash
# install.sh - Install Zero-HID_MQTT on Linux
# https://github.com/ben-jam1n/Zero-HID_MQTT
# This script automates setup on Linux systems (Raspberry Pi, Debian, Ubuntu, etc.)
# Requires: sudo access

set -e

# 1. Install system dependencies
echo "Step 1: Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip git


# 2 Install USB Gadget Module (if on Raspberry Pi)
echo "Step 2: Installing zero-hid USB Gadget module..."
zero-hid_DIR="/opt/Zero-HID"
zero-hid_GITHUB_URL="https://github.com/thewh1teagle/zero-hid"

# 2.1 Create install directory
echo "Creating zero-hid installation directory..."
sudo mkdir -p "$zero-hid_DIR"
sudo chown $USER:$USER "$zero-hid_DIR"

# 2.2. Clone repository
echo "Cloning repository..."
if [ -d "$zero-hid_DIR/.git" ]; then
    echo "Repository already exists, pulling latest changes..."
    cd "$zero-hid_DIR" && git pull
else
    git clone "$zero-hid_GITHUB_URL" "$zero-hid_DIR"
fi

# 2.3 Install zero-hid usb_gadget module
echo "Installing zero-hid USB Gadget module..."
cd $zero-hid_DIR && cd ./usb_gadget
sudo ./installer

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


# Final instructions
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit the configuration file:"
echo "   sudo nano $INSTALL_DIR/config.yaml"
echo "2. Update MQTT broker settings and monitor controls"
echo "3. Start the service:"
echo "   sudo systemctl start Zero-HID_MQTT.service"
echo "4. Check service status:"
echo "   sudo systemctl status Zero-HID_MQTT.service"
echo "5. View logs in real-time:"
echo "   sudo journalctl -u Zero-HID_MQTT.service -f"
echo ""
echo "For more information, see README.md on https://github.com/ben-jam1n/Zero-HID_MQTT"
echo "=========================================="
