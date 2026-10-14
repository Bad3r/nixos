# Remote desktop with RustDesk

RustDesk shares each host's live X11 session and its login screen with the other hosts and the iPhone, with clipboard, audio, and file transfer.
[rustdesk.nix](../../modules/apps/rustdesk.nix) runs the client service on every host.
The ID server (hbbs) and relay (hbbr) run on the host whose `modules/<host>/policy.nix` sets `rustdeskServer`.
No device contacts RustDesk's public servers.

## Privacy model

- hbbs and hbbr answer on the [Cloudflare Mesh](../cloudflare/warp/README.md) interface only.
- A session connects the two devices directly over Mesh and falls back to the relay when that connection fails.
- hbbs signs each device's key with the pair in `secrets/rustdesk.yaml`, which lets peers encrypt each session end to end.
  Neither the relay nor Cloudflare's edge sees the screen or the clipboard.
- Direct IP sessions are off, since they skip that key exchange and would cross Cloudflare in the clear.
- A host refuses sessions from addresses outside the Mesh allocation and accepts only its permanent password.
- One-time passwords, TCP tunnels, the remote terminal, and the camera are off.
- The client service, the session processes it starts, and both servers reach only loopback and the CGNAT block holding the Mesh.
  A fallback to a public server or any other call home fails in the kernel.
- The client's heartbeat, sysinfo, and audit uploads, its update check, and LAN discovery are off, and the hbbs build has no update check.

Some traffic stays visible:

- Registration with hbbs is plaintext UDP inside the tunnel, so Cloudflare can read each device's RustDesk ID and, at first registration, its machine ID.
- The iOS app checks for updates and probes public STUN servers at launch, and no setting stops either.

The service rewrites its managed settings at every start, so a GUI change to one of them lasts until the next restart.
Change those settings in `rustdesk.nix` instead.

## Set up a host

Precondition: the host is enrolled in Cloudflare WARP and runs a generation with RustDesk.

1. Open RustDesk, go to Settings, Security, and set a permanent password.
   Use a long random one, since a captured login proof can be guessed offline.

2. Optionally, turn on two-factor authentication on the same tab and scan the code into an authenticator.

3. Print the ID other devices connect to:

   ```sh
   rustdesk --get-id
   ```

The main window reports the service as ready once hbbs accepts the registration.
The password and the two-factor secret live in RustDesk's own configuration under `/root`, so a reinstalled host needs both set again.

## Connect

Enter the other device's ID in the main window and log in with its permanent password.
A session that cannot connect directly runs through the relay and loads the server host's uplink.

## Set up the iPhone

Precondition: the iPhone is connected to the Zero Trust team and reaches the Mesh.

1. On a host, from the repository root, read the server host's Mesh address and the public key:

   ```sh
   getent hosts <server>.internal
   sops -d --extract '["server_public_key"]' secrets/rustdesk.yaml
   ```

2. In the RustDesk app, open Settings, ID/Relay server, enter the address as the ID server and the public key as the Key, and leave the API server empty.

3. Connect to a host ID and check that the session's shield shows an encrypted connection.

Repeat step 2 after the server host's Mesh address changes or the key pair is replaced.

## Troubleshooting

### "Key mismatch"

Cause: the device's Key setting differs from the server's public key.
Fix: paste the key from `secrets/rustdesk.yaml` again, as in the iPhone setup.

### "Insecure Connection" before the session opens

Cause: the device could not check the peer's key against the hbbs signature, usually because its Key setting is empty.
Fix: cancel the connection, since continuing sends the session unencrypted over Cloudflare, and set the Key.

### Pointer moves but clicks and keys do nothing

Cause: the session process cannot load libxdo, which RustDesk opens at runtime for X11 input.
Diagnose with `grep -r "xdo context" ~/.local/share/logs/RustDesk/server/`.
Fix: the `rustdesk-flutter` package needs xdotool's library directory in the rpath of `librustdesk.so`.

[RustDesk documentation](https://rustdesk.com/docs/en/)
