# Zero-HID to MQTT

**Emulate an HID device with a Raspberry PI and initiate basic keyboard/mouse actions via MQTT**

Adds a MQTT layer to allow remotely triggering keyboard/mouse actions from automation platforms such as Home Assistant. 

## Hardware Requirements

- **Raspberry Pi Zero / Zero 2 W** (or other Pi with USB gadget mode support)
- **Data-capable USB cable** (not power-only) - This is critical!
- **Direct USB connection** to host computer (USB hubs may not work reliably with gadget mode)

**Important:** The Pi Zero 2 W has two micro-USB ports—one for power (PWR) and one for data. Use the **data port**, not the power port. Some USB cables only carry power; if setup doesn't work, try a different cable.

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ben-jam1n/Zero-HID_MQTT/main/install.sh)"
```

The installer will:
1. Install the zero-hid USB gadget module
2. Remove any conflicting `g_ether` drivers
3. Verify HID devices are created
4. Set up the systemd service
5. Create a Python virtual environment with dependencies

## Quick Start

### 1. Configure

```bash
cp /opt/Zero-HID_MQTT/example_config.yaml /opt/Zero-HID_MQTT/config.yaml
sudo nano /opt/Zero-HID_MQTT/config.yaml
```

Update these fields:
```yaml
mqtt_broker: 192.168.1.100      # Your MQTT broker IP
mqtt_port: 1883
mqtt_username: your_username
mqtt_password: your_password
device_name: Control_Room       # Unique name (no spaces)
```

See `example_config.yaml` for control examples.

### 2. Create Macros (Optional)

For complex sequences, edit `macros.yaml`. See `example_macros.yaml` for 10 real-world examples.

### 3. Start

```bash
sudo systemctl start Zero-HID_MQTT.service
sudo systemctl status Zero-HID_MQTT.service
sudo journalctl -u Zero-HID_MQTT.service -f    # View logs
```

### 4. Connect

Physically connect the Pi via USB to your computer. It should discover in Home Assistant.

## Configuration

### Controls (config.yaml)

Define buttons and switches in the `controls:` section. Two main types:

**Button** - Executes a macro one time when pressed:
```yaml
- name: Lock Screen
  key: lock_screen
  entity_type: button
  HID_type: keyboard
  Modifiers: [MOD_LEFT_GUI]
  KeyCodes: [KEY_L]
```

**Switch** - Turns a looping macro ON/OFF (macro repeats while switch is ON):
```yaml
- name: Repeat Sequence
  key: repeat_macro
  entity_type: switch
  macro: repeat_text    # Macro loops endlessly while switch is ON
```

**Macro-Based Button** - Complex sequences:
```yaml
- name: Fill Login Form
  key: login_macro
  entity_type: button
  macro: login_credentials    # Defined in macros.yaml
```

See `example_config.yaml` for complete examples with all options.

### Macros (macros.yaml)

Define complex sequences with typing, key presses, and delays:

```yaml
macros:
  login_credentials:
    delay_between_actions: 100  # ms between actions
    actions:
      - type: "type"
        text: "username"
      - type: "key"
        key: "KEY_TAB"
      - type: "type"
        text: "password"
      - type: "key"
        key: "KEY_RETURN"
```

**Action Types:**
- `type: "text"` - Type text
- `key: KEY_NAME` - Press single key (add `modifiers: [MOD_...]` for combinations)
- `key_combo:` - Press multiple modifiers + key simultaneously
- `delay: {ms: 500}` - Wait 500 milliseconds

**Modifiers:** `MOD_LEFT_CTRL`, `MOD_LEFT_SHIFT`, `MOD_LEFT_ALT`, `MOD_LEFT_GUI`, etc.

**Key Codes:** See full list at https://github.com/thewh1teagle/zero-hid/blob/main/zero_hid/hid/keycodes.py

Examples: `KEY_A`, `KEY_RETURN`, `KEY_TAB`, `KEY_SYSRQ`, `KEY_VOLUMEMUTE`, etc.

See `example_macros.yaml` for 11 ready-to-use examples.

### Switches vs Buttons

**Buttons** (one-time execution):
- Click in Home Assistant → macro runs once
- Useful for: single tasks, form fills, shortcuts

**Switches** (repeating loops):
- Turn ON in Home Assistant → macro loops endlessly
- Turn OFF in Home Assistant → macro stops
- Useful for: testing, automated repeated sequences, holding down keys virtually
- The macro runs continuously until you turn the switch OFF
- Add a delay in your macro to control loop speed

### MQTT Topics

```
hid_control/YOUR_DEVICE_NAME/command      # Receives button presses
hid_control/YOUR_DEVICE_NAME/state        # Publishes status
hid_control/YOUR_DEVICE_NAME/ip_address   # Diagnostic sensor
```

## Troubleshooting

Run diagnostics:
```bash
bash /opt/Zero-HID_MQTT/troubleshoot.sh
```

### "Cannot send after transport endpoint shutdown"

The HID device can't communicate with USB host.

**Solutions:**
- Try a different USB cable (some are power-only)
- Connect directly to computer (not via hub)
- Use correct USB port on Pi
- Reboot: `sudo reboot`

### "UDC core: couldn't find an available UDC or it's busy"

USB gadget initialization failed (usually `g_ether` conflict).

**Solution:**
```bash
sudo sed -i 's/modules-load=dwc2,g_ether/modules-load=dwc2/g' /boot/firmware/cmdline.txt
sudo reboot
```

### Service not sending commands

Check logs:
```bash
sudo journalctl -u Zero-HID_MQTT.service -f
```

Common causes: USB not connected, MQTT unreachable, YAML syntax error.

### Missing tools

If troubleshoot.sh errors on missing commands:
```bash
sudo apt-get install -y lsof net-tools
```

## Service Management

```bash
sudo systemctl start Zero-HID_MQTT.service      # Start
sudo systemctl stop Zero-HID_MQTT.service       # Stop
sudo systemctl restart Zero-HID_MQTT.service    # Restart
sudo systemctl status Zero-HID_MQTT.service     # Status
sudo journalctl -u Zero-HID_MQTT.service -f     # Live logs
```







## Credits
This relies on the work from the Zero-hid library: https://github.com/thewh1teagle/zero-hid/

Keycode Reference: 
https://github.com/thewh1teagle/zero-hid/blob/main/zero_hid/hid/keycodes.py
