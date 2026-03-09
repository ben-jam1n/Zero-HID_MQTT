# Zero-HID to MQTT

**Emulate an HID device with a Raspberry PI and initiate basic keyboard/mouse actions via MQTT**

Currently in early testing phase. 

Adds a MQTT layer to allow remotly triggering keyboard/mouse actions from automation platforms such as Home Assistant. 
Designed to be ran on the same device running [ddcutil_mqtt](https://github.com/ben-jam1n/ddcutil_mqtt) controlling monitor inputs/settings allowing for further workstation automation and control. 

### Semi-Automated Installation
The `install.sh` script will clone the repository to a local directory, install dependencies, and set up the script as a systemd service.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ben-jam1n/Zero-HID_MQTT/main/install.sh)"
```

## Credits:
This relies on the work from the Zero-hid library: https://github.com/thewh1teagle/zero-hid/

Keycode Reference: 
https://github.com/thewh1teagle/zero-hid/blob/main/zero_hid/hid/keycodes.py
