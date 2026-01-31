# USBGuard Configuration

This repository uses [USBGuard](https://usbguard.github.io/) to control USB device access. Rules are stored encrypted via sops at `secrets/usbguard/system76.yaml`.

## Adding New Devices

1. Connect the device and check what's blocked:

   ```bash
   usbguard list-devices | grep -i block
   ```

2. Temporarily allow the device (runtime only):

   ```bash
   sudo usbguard allow-device <id>
   ```

3. Copy the **exact** rule output and add it to the sops-encrypted rules file (see [sops docs](../sops/README.md#programmatic--scripted-editing) for safe editing procedures).

4. Deploy the configuration:
   ```bash
   ./build.sh
   ```

## Gotchas

### Device Names Must Match Exactly

USBGuard performs **exact string matching** on device names, including trailing whitespace. If a device reports its name with padding:

```
name "USB 2.0 BILLBOARD             "
```

Your rule must include those trailing spaces verbatim. Copying directly from `usbguard list-devices` output ensures accuracy.

### USB Hubs Create Device Hierarchies

Allowing a USB hub does **not** automatically allow devices connected through it. Each child device must be explicitly allowed:

```
Parent Hub (2109:2813) ← allowed
  └── Child Hub (05e3:0618) ← must also be allowed
        └── Storage (05e3:0752) ← must also be allowed
        └── Ethernet (0bda:8153) ← must also be allowed
```

When you connect a USB-C dock or hub, expect to allow multiple devices in sequence as each layer of the hierarchy enumerates.

### Devices May Present Multiple Identities

Some devices (especially network adapters) present different USB product IDs or interfaces depending on their mode:

| Mode         | ID        | Interface                  |
| ------------ | --------- | -------------------------- |
| Network      | 0bda:8153 | ff:ff:00 02:06:00 0a:00:00 |
| Mass Storage | 0bda:8151 | 08:06:50                   |

Add rules for **all** observed identities to ensure the device works across reconnects and mode switches.

### Runtime vs Persistent Rules

- `sudo usbguard allow-device <id>` - Runtime only, lost on reboot/service restart
- Rules in `secrets/usbguard/system76.yaml` - Persistent, applied on activation

Always add devices to the encrypted rules file after testing with runtime allows.

## Rule Format

```
allow id <vendor>:<product> serial "<serial>" name "<name>" hash "<hash>" parent-hash "<parent-hash>" via-port "<port>" with-interface <interfaces> with-connect-type "<type>"
```

Key fields:

- `hash` - Unique device fingerprint (most reliable identifier)
- `parent-hash` - Hash of the parent hub (establishes hierarchy)
- `with-interface` - USB interface classes (can be single or `{ multiple }`)
- `with-connect-type` - "hotplug", "hardwired", or "unknown"

## Troubleshooting

| Symptom                              | Cause                            | Fix                                              |
| ------------------------------------ | -------------------------------- | ------------------------------------------------ |
| Device blocked after adding rule     | Name mismatch (whitespace)       | Copy exact name from `usbguard list-devices`     |
| Child devices blocked                | Hub hierarchy                    | Allow each device in the chain                   |
| Device works sometimes               | Multiple identities              | Add rules for all observed IDs                   |
| `IPC ERROR: device id doesn't exist` | Device re-enumerated with new ID | Re-run `usbguard list-devices` to get current ID |
