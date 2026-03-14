"""
zero-HID_MQTT - Remote HID control via MQTT for Home Assistant
https://github.com/ben-jam1n/Zero-HID_MQTT

This script implements a service that listens for MQTT messages to send HID commandsto a connected device using the zero-HID library. It allows you to integrate basic keyboard/mouse commands of any device into Home Assistant or any MQTT-compatible system.
"""

# =========================
# Imports and Dependencies
# =========================
import json
import os
import sys
import paho.mqtt.client as mqtt
import time
import threading
import functools
import socket
from zero_hid import Mouse, Keyboard, KeyCodes




try:
    import yaml
except ImportError:
    yaml = None

__version__ = "0.1.0"

# =========================
# Config Loading Utilities
# =========================
def load_config(config_path):
    """Load YAML config file."""
    if not os.path.exists(config_path):
        print(f"Config file not found: {config_path}")
        sys.exit(1)
    ext = os.path.splitext(config_path)[1].lower()
    with open(config_path, "r") as config_file:
        return yaml.safe_load(config_file)

def load_macros(macros_path):
    """Load macros YAML file. Returns empty dict if file doesn't exist."""
    if not os.path.exists(macros_path):
        return {}
    try:
        with open(macros_path, "r") as macros_file:
            macros_config = yaml.safe_load(macros_file)
            return macros_config.get("macros", {}) if macros_config else {}
    except Exception as e:
        print(f"Warning: Could not load macros file {macros_path}: {e}")
        return {}

# =========================
# Logging Setup
# =========================
def setup_logging(log_level):
    """
    Set up logging optimized for systemd services.
    Logs to stdout/stderr which systemd captures and manages automatically.
    Includes rate limiting to prevent log spam and SD card overflow.
    """
    import logging
    import logging.handlers
    
    # Create logger
    logger = logging.getLogger(__name__)
    logger.setLevel(getattr(logging, log_level, logging.DEBUG))
    
    # Clear any existing handlers to avoid duplicates
    if logger.handlers:
        logger.handlers.clear()
    
    # Create formatter optimized for systemd (no timestamp since systemd adds it)
    formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
    
    # Console handler for systemd to capture
    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, log_level, logging.DEBUG))
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    logger.info("Logging configured for systemd service (viewable with: journalctl -u Zero-HID_MQTT.service)")
    return logger

# =========================
# Local IP Address Utility (for diagnostics)
# =========================
def get_local_ip(broker_ip):
    """
    Determines the local IP address by simulating a connection to the MQTT broker.
    This doesn't actually connect, just determines which local interface would be used.
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect((broker_ip, 80))
            local_ip = s.getsockname()[0]
        return local_ip
    except Exception as e:
        raise RuntimeError(f"Unable to determine LAN IP: {e}")
    

# =========================
# Main Application Logic
# =========================
def run_macro_loop(control_key, macro_name, macros, stop_event, logger, execute_macro):
    """
    Run a macro repeatedly in a loop until stop_event is set.
    Used for switch-type controls that can loop endlessly.
    """
    loop_count = 0
    logger.info(f"Starting macro loop for control '{control_key}' (macro: {macro_name})")
    
    while not stop_event.is_set():
        loop_count += 1
        logger.debug(f"  Loop iteration {loop_count}")
        try:
            execute_macro(macro_name)
        except Exception as e:
            logger.error(f"Error in macro loop for '{control_key}': {e}")
        
        # Small delay between loop iterations to avoid overwhelming the system
        # (but responsive to stop_event)
        if not stop_event.wait(0.1):  # Check event every 100ms
            pass
    
    logger.info(f"Stopped macro loop for control '{control_key}' after {loop_count} iterations")


def main():
    """Main entry point for Zero-HID_MQTT."""
    # Track active switch loops: {control_key: threading.Event}
    active_switches = {}
    script_dir = os.path.dirname(os.path.realpath(__file__))
    default_config_path = os.path.join(script_dir, "config.yaml")
    config_path = sys.argv[1] if len(sys.argv) > 1 else default_config_path
    config = load_config(config_path)

    # Load macros (optional file)
    macros_path = os.path.join(script_dir, "macros.yaml")
    macros = load_macros(macros_path)


    log_level = config.get("log_level", "INFO").upper()
    logger = setup_logging(log_level)

    # --- MQTT Setup ---
    MQTT_BROKER = config["mqtt_broker"]
    MQTT_PORT = config["mqtt_port"]
    MQTT_USERNAME = config["mqtt_username"]
    MQTT_PASSWORD = config["mqtt_password"]

    DEVICE_NAME = config["device_name"]
    SANITIZED_DEVICE_NAME = DEVICE_NAME.replace(" ", "_")
    TOPIC_PREFIX = f"hid_control/{SANITIZED_DEVICE_NAME}"

    MQTT_TOPIC_COMMAND = f"{TOPIC_PREFIX}/command"
    MQTT_TOPIC_STATE = f"{TOPIC_PREFIX}/state"

    # Get local IP address for diagnostics sensor
    try:
        local_ip = get_local_ip(MQTT_BROKER)
    except Exception as e:
        logger.warning(f"Could not determine local IP address: {e}")
        local_ip = "unknown"

    # ---  ---
    def handle_errors(func):
        """Decorator to handle errors in HID commands."""
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                logger.error(f"Error in {func.__name__}: {e}")
                return None
        return wrapper
    
    @handle_errors
    def restart_service():
        """Trigger a service restart by exiting the process.
        
        When running under systemd with Restart=always, simply exiting
        will cause systemd to automatically restart the service.
        """
        try:
            logger.info("Exiting process to trigger systemd restart")
            sys.exit(0)
        except Exception as e:
            logger.error(f"Error during restart: {e}")
            return False
    
    def resolve_keycode(name: str):
        """Helper function to resolve string keycode names to KeyCodes objects."""
        # Strip "KeyCodes." prefix if present in config
        if name.startswith("KeyCodes."):
            name = name[9:]
        resolved = getattr(KeyCodes, name, None)
        logger.debug(f"Resolved '{name}' to {resolved}")
        return resolved
    
    @handle_errors
    def execute_macro(macro_name: str):
        """Execute a macro defined in macros.yaml."""
        if macro_name not in macros:
            logger.error(f"Macro not found: {macro_name}")
            return False
        
        macro = macros[macro_name]
        actions = macro.get("actions", [])
        global_delay = macro.get("delay_between_actions", 100)  # Default 100ms
        
        logger.info(f"Executing macro: {macro_name}")
        logger.debug(f"Macro has {len(actions)} actions")
        
        try:
            for idx, action in enumerate(actions):
                action_type = action.get("type")
                
                if action_type == "type":
                    # Type text
                    text = action.get("text", "")
                    logger.debug(f"  Action {idx}: type '{text}'")
                    with Keyboard() as k:
                        k.write(text)
                
                elif action_type == "key":
                    # Press single key (with optional modifiers)
                    key_name = action.get("key")
                    modifiers = action.get("modifiers", [])
                    
                    # Resolve modifiers
                    mod_codes = [resolve_keycode(m) for m in modifiers]
                    mod_codes = [m for m in mod_codes if m is not None]
                    
                    # Resolve main key
                    key_code = resolve_keycode(key_name)
                    if key_code is None:
                        logger.warning(f"  Action {idx}: Unknown key {key_name}")
                        continue
                    
                    logger.debug(f"  Action {idx}: key {key_name} with modifiers {modifiers}")
                    with Keyboard() as k:
                        if mod_codes:
                            k.press(mod_codes, key_code)
                        else:
                            k.press([], key_code)
                
                elif action_type == "key_combo":
                    # Press multiple keys simultaneously (key combination)
                    modifiers = action.get("modifiers", [])
                    key_name = action.get("key")
                    
                    # Resolve all modifiers
                    mod_codes = [resolve_keycode(m) for m in modifiers]
                    mod_codes = [m for m in mod_codes if m is not None]
                    
                    # Resolve main key
                    key_code = resolve_keycode(key_name)
                    if key_code is None:
                        logger.warning(f"  Action {idx}: Unknown key {key_name}")
                        continue
                    
                    logger.debug(f"  Action {idx}: key_combo {modifiers} + {key_name}")
                    with Keyboard() as k:
                        k.press(mod_codes, key_code)
                
                elif action_type == "delay":
                    # Wait for specified milliseconds
                    delay_ms = action.get("ms", 100)
                    delay_sec = delay_ms / 1000.0
                    logger.debug(f"  Action {idx}: delay {delay_ms}ms")
                    time.sleep(delay_sec)
                
                else:
                    logger.warning(f"  Action {idx}: Unknown action type '{action_type}'")
                    continue
                
                # Add delay between actions (unless it was a delay action itself)
                if action_type != "delay" and idx < len(actions) - 1:
                    time.sleep(global_delay / 1000.0)
            
            logger.info(f"Macro execution complete: {macro_name}")
            return True
            
        except Exception as e:
            logger.error(f"Error executing macro '{macro_name}': {e}")
            return False
        
    # Centralized MQTT state publishing
    def publish_state(client, topic, value, retain=True):
        client.publish(topic, value, retain=retain)

    # Ensure discovery messages are retained
    def publish_discovery(client):
        """Publish Home Assistant discovery messages."""
        logger.debug("Publishing MQTT discovery messages...")
        discovery_payloads = []
        device_info = {
                "identifiers": [SANITIZED_DEVICE_NAME],
                "name": f"{DEVICE_NAME}",
                "manufacturer": "ben-jam1n",
                "configuration_url": "https://github.com/ben-jam1n/zero-hid_mqtt",
                "model": "Zero-HID_MQTT",
        }
        origin_info = {
                "support_url": "https://github.com/ben-jam1n/zero-hid_mqtt",
                "name": "Zero-HID_MQTT",
        }
        
        # Add IP Address as a diagnostic sensor
        ip_sensor_payload = {
            "name": "IP Address",
            "state_topic": f"{TOPIC_PREFIX}/ip_address",
            "device": device_info,
            "origin": origin_info,
            "unique_id": f"{SANITIZED_DEVICE_NAME}_ip_address",
            "entity_category": "diagnostic",
            "icon": "mdi:network"
        }
        ip_sensor_topic = f"homeassistant/sensor/{SANITIZED_DEVICE_NAME}_ip_address/config"
        discovery_payloads.append({"topic": ip_sensor_topic, "payload": ip_sensor_payload})
        
        # Publish the IP address value
        client.publish(f"{TOPIC_PREFIX}/ip_address", local_ip, retain=True)


        for control in config["controls"]:
            key = control["key"] # Unique key for this control (used in MQTT payloads)
            name = control["name"] # Friendly name for Home Assistant 
            entity_category = control.get("entity_category") # Optional: control, config, diagnostic, or omit for none
            
            if control["entity_type"] == "button":
                button_payload = {
                    "name": name,
                    "command_topic": MQTT_TOPIC_COMMAND,
                    "payload_press": f"{key}:press",
                    "device": device_info,
                    "origin": origin_info,
                    "unique_id": f"{SANITIZED_DEVICE_NAME}_{key}_button"
                }
                if entity_category:
                    button_payload["entity_category"] = entity_category
                button_topic = f"homeassistant/button/{SANITIZED_DEVICE_NAME}_{key}/config"
                discovery_payloads.append({"topic": button_topic, "payload": button_payload})
            
            elif control["entity_type"] == "switch":
                switch_payload = {
                    "name": name,
                    "command_topic": MQTT_TOPIC_COMMAND,
                    "state_topic": f"{TOPIC_PREFIX}/{key}/state",
                    "payload_on": f"{key}:on",
                    "payload_off": f"{key}:off",
                    "state_on": "on",
                    "state_off": "off",
                    "device": device_info,
                    "origin": origin_info,
                    "unique_id": f"{SANITIZED_DEVICE_NAME}_{key}_switch"
                }
                if entity_category:
                    switch_payload["entity_category"] = entity_category
                switch_topic = f"homeassistant/switch/{SANITIZED_DEVICE_NAME}_{key}/config"
                discovery_payloads.append({"topic": switch_topic, "payload": switch_payload})

        for item in discovery_payloads:
            result = client.publish(item["topic"], json.dumps(item["payload"]), retain=True)
            logger.debug(f"Published to {item['topic']} with result: {result}")


    # MQTT Callback: When a message is received
    def on_message(client, userdata, msg):
        """Handle incoming MQTT messages."""
        try:
            # Decode the incoming MQTT payload to UTF-8 string
            payload = msg.payload.decode("utf-8")
            logger.debug(f"Received message: {payload} on topic: {msg.topic}")
            
            # Parse the payload to extract command and optional value (format: "command:value")
            if ":" in payload:
                command, value = payload.split(":", 1)
            else:
                command, value = payload, None
            
            # Look up the control configuration matching this command key
            control = next((c for c in config["controls"] if c["key"] == command), None)
            
            # Process the control if found in config
            if control:
                HID_type = control.get("HID_type")
                
                # Check if this is a special restart button for the service
                if control.get("is_restart_button", False):
                    # Handle service restart button
                    logger.info("Restart button pressed from Home Assistant")
                    if restart_service():
                        publish_state(client, f"{TOPIC_PREFIX}/{command}_state", "success")
                        logger.info("Service restart will occur in a moment (connection may drop)")
                    else:
                        publish_state(client, f"{TOPIC_PREFIX}/{command}_state", "error")
                        logger.error("Failed to initiate service restart")
                
                # ===== SWITCH HANDLING =====
                # Handle switch-type controls with looping macros
                elif control["entity_type"] == "switch" and control.get("macro"):
                    macro_name = control["macro"]
                    
                    if value == "on":
                        # Turn switch ON - start the macro loop
                        if command not in active_switches:
                            logger.info(f"Switch '{command}' turned ON - starting macro loop")
                            stop_event = threading.Event()
                            active_switches[command] = stop_event
                            
                            # Start the macro loop in a background thread
                            loop_thread = threading.Thread(
                                target=run_macro_loop,
                                args=(command, macro_name, macros, stop_event, logger, execute_macro),
                                daemon=True
                            )
                            loop_thread.start()
                            publish_state(client, f"{TOPIC_PREFIX}/{command}/state", "on")
                        else:
                            logger.debug(f"Switch '{command}' already running")
                    
                    elif value == "off":
                        # Turn switch OFF - stop the macro loop
                        if command in active_switches:
                            logger.info(f"Switch '{command}' turned OFF - stopping macro loop")
                            active_switches[command].set()  # Signal the thread to stop
                            del active_switches[command]
                            publish_state(client, f"{TOPIC_PREFIX}/{command}/state", "off")
                        else:
                            logger.debug(f"Switch '{command}' already stopped")
                
                # ===== BUTTON HANDLING =====
                # Handle macro-based button controls
                elif control["entity_type"] == "button" and control.get("macro"):
                    macro_name = control["macro"]
                    logger.debug(f"Executing macro from button control: {macro_name}")
                    if execute_macro(macro_name):
                        publish_state(client, f"{TOPIC_PREFIX}/{command}_state", "success")
                    else:
                        publish_state(client, f"{TOPIC_PREFIX}/{command}_state", "error")
                
                # Handle keyboard button controls (legacy direct HID_action)
                elif control["entity_type"] == "button" and HID_type == "keyboard":
                    # Get list of HID actions (keycodes and modifiers) from config
                    mod_keys = control.get("Modifiers", [])
                    key_codes = control.get("KeyCodes", [])
                    
                    logger.debug(f"Raw modifiers from config: {mod_keys}")
                    logger.debug(f"Raw keycodes from config: {key_codes}")

                    # Resolve modifier keys and main keys to actual KeyCodes objects
                    modifiers = []
                    main_keys = []
                    
                    for mod in mod_keys:
                        keycode = resolve_keycode(mod)
                        if keycode is not None:
                            modifiers.append(keycode)
                        else:
                            logger.warning(f"Unknown modifier keycode: {mod}")
                    
                    for key in key_codes:
                        keycode = resolve_keycode(key)
                        if keycode is not None:
                            main_keys.append(keycode)
                        else:
                            logger.warning(f"Unknown key keycode: {key}")
                            
                    # Execute the keyboard keypress with resolved modifiers and keys
                    logger.debug("Calling zero-HID with modifiers: %s and main keys: %s", modifiers, main_keys)
                    with Keyboard() as k:
                        for key in main_keys:
                            k.press(modifiers, key)

            else:
                # Command key not found in config
                logger.warning(f"Unknown command: {command}")
                publish_state(client, MQTT_TOPIC_STATE, "unknown")
        except Exception as e:
            # Catch any errors and publish error state
            logger.error(f"Error processing message: {e}")
            publish_state(client, MQTT_TOPIC_STATE, "error")

    # --- Systemd Service & Main Loop ---
    def on_connect(client, userdata, flags, rc):
        """Handle MQTT connection events."""
        logger.info(f"Connected to MQTT broker with result code {rc}")
        client.subscribe(MQTT_TOPIC_COMMAND)
        publish_discovery(client)

    client = mqtt.Client()
    # Only enable MQTT client logging for DEBUG level to reduce log spam
    if log_level == "DEBUG":
        client.enable_logger(logger)
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_message = on_message


    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_forever()



# =========================
# Script Entrypoint
# =========================
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(f"\nZero-HID_MQTT v{__version__}\nUsage: python Zero-HID_MQTT.py [config_path]\nIf no config_path is provided, defaults to config.yaml in the script directory.\nSupports .json, .yaml, and .yml config files.\n")
        sys.exit(0)
    main()