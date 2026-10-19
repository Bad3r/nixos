# Remote desktop with RustDesk

RustDesk shares each host's live X11 session and its login screen with the other hosts and the iPhone, with clipboard, audio, and file transfer.
[rustdesk/nixos.nix](../../modules/apps/rustdesk/nixos.nix) runs the client service on every host.
The ID server (hbbs) and relay (hbbr) run on the host whose `modules/hosts/<host>/policy.nix` sets `rustdeskServer`.
No host contacts RustDesk's public servers.

## Privacy model

- hbbs and hbbr answer on the [Cloudflare Mesh](../apps/cloudflare/warp/README.md) interface only.
- A session connects the two devices directly over Mesh and falls back to the relay when that connection fails.
- hbbs signs each device's key with the pair in `secrets/rustdesk.yaml`, which lets peers encrypt each session end to end.
  Neither the relay nor Cloudflare's edge sees the screen or the clipboard.
- Direct IP sessions are off, since they skip that key exchange and would cross Cloudflare in the clear.
- A host refuses sessions from addresses outside the Mesh allocation and accepts only the fleet password.
- One-time passwords and RustDesk's own TCP tunnels, remote terminal, and camera are off.
- Remote restart is off, since a restarted host waits at its LUKS passphrase prompt.
- The client service, the session processes it starts, and both servers reach only loopback and the Mesh range.
  Their fallback to a public server or any other call home fails in the kernel.
- The GUI runs in the user's session without that kernel limit, so only its settings keep its traffic on Mesh.
- The client's heartbeat, sysinfo, and audit uploads, its update check, and LAN discovery are off, and the hbbs build has no update check.
- Each host's ID derives from the server key, where RustDesk's default ID encodes part of the MAC address.

Some traffic stays visible:

- Registration with hbbs is plaintext UDP inside the tunnel, so Cloudflare can read each device's RustDesk ID and machine ID.
- The iOS app checks for updates and probes public STUN servers at launch, and no setting stops either.

## Logins

Every host accepts the password in `secrets/rustdesk.yaml`, kept in RustDesk's configuration as a salted hash.
Every other host appears by name under Favorites and Recent sessions, carrying that login, so a session between hosts opens without a prompt.
Those entries skip the default codec, frame rate, and a few other Display settings, so set them per host from the session toolbar.

The service rewrites the ID, the password, the stored logins, the favorites, and the managed settings at every start.
A GUI change to one of them lasts until the next restart.
Change those settings in `rustdesk.nix` instead.
A RustDesk window open across a restart writes back the favorites and GUI settings it loaded, so close RustDesk windows before restarting the service.

Print a host's ID on that host:

```sh
rustdesk --get-id
```

## Connect

Pick the host under Favorites, or type part of its name or ID in the ID field and take the suggestion.
A session that cannot connect directly runs through the relay and loads the server host's uplink.

## Set up the iPhone

Precondition: the iPhone is connected to the Zero Trust team and reaches the Mesh.

1. On a host, from the repository root, read the server host's Mesh address, the public key, and the password:

   ```sh
   getent hosts <server>.internal
   sops -d --extract '["server_public_key"]' secrets/rustdesk.yaml
   sops -d --extract '["password"]' secrets/rustdesk.yaml
   ```

2. In the RustDesk app, open Settings, ID/Relay server, enter the address as the ID server and the public key as the Key, and leave the API server empty.

3. Connect to each host's ID, enter the password with Remember password checked, and check that the session's shield shows an encrypted connection.

Repeat step 2 after the server host's Mesh address changes or the key pair is replaced, and step 3 after the password or the key pair is replaced.
A new key pair also gives every host a new ID.
Delete the entries with the old IDs under Recent sessions on each host and on the iPhone, which also clears them from Favorites.

## Troubleshooting

### "Key mismatch"

Cause: the device's Key setting differs from the server's public key.
Fix: paste the key from `secrets/rustdesk.yaml` again, as in the iPhone setup.

### "Insecure Connection" before the session opens

Cause: the device could not check the peer's key against the hbbs signature, usually because its Key setting is empty.
Fix: cancel the connection, since continuing sends the session unencrypted over Cloudflare, and set the Key.

### Password prompt for another host

Cause: that host's entry left the peer list, for example through Delete in the main window.
Fix: restart the service, which writes the entry again:

```sh
sudo systemctl restart rustdesk
```

### A reinstalled host comes up under a random ID

Cause: hbbs ties each ID to the machine ID that first registered it, and a reinstall brings a new machine ID.
Fix: on the server host, drop the old registration, where `<id>` is the ID the other hosts list for the reinstalled host, not the random one:

```sh
sudo systemctl stop rustdesk-signal
sudo sqlite3 /var/lib/rustdesk/db_v2.sqlite3 "delete from peer where id = '<id>'"
sudo systemctl start rustdesk-signal
```

Then, on the reinstalled host, restart the service, which writes the derived ID again:

```sh
sudo systemctl restart rustdesk
```

[RustDesk documentation](https://rustdesk.com/docs/en/)
