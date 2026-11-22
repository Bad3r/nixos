# Windows RDP host setup

`scripts/windows/rdp-host-setup.ps1` prepares a Windows 10 or 11 host as an AVC444 Remote Desktop target for Remmina over the Cloudflare WARP Mesh.
It writes the Remote Desktop policies into the local machine policy file (`Registry.pol`, the file `gpedit.msc` edits), so they appear in gpedit and survive policy refreshes.
It also sets the 60 fps frame cap, opens RemoteApp to any installed program, and enables OpenSSH and WinRM for the Mesh range only.
Each value carries its gpedit path and reason in a comment beside it in the script.
Failures and their fixes are on [windows-host-troubleshooting.md](windows-host-troubleshooting.md).

## Configure a host

Precondition: the host is enrolled in the WARP Mesh, and an account with local administrator rights is signed in over RDP or at the console.

1. Copy `scripts/windows/rdp-host-setup.ps1` to the host, for example through a Remmina shared folder.

2. List the SSH public keys on songbird; the key to install is one of these lines:

   ```sh
   ssh-add -L
   ```

3. In an elevated PowerShell in the script's folder, allow the script for this session and report the current state:

   ```powershell
   Unblock-File .\rdp-host-setup.ps1
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
   .\rdp-host-setup.ps1 -Check
   ```

4. Apply the settings, passing the public key from step 2:

   ```powershell
   .\rdp-host-setup.ps1 -AuthorizedKey 'ssh-ed25519 AAAA... comment'
   ```

5. Disconnect and reconnect, since a running session keeps the graphics settings it started with.

Verification: `.\rdp-host-setup.ps1 -Check` prints `all settings match` and exits 0.

Every step is idempotent, so the same command re-applies the settings after a Windows update or a domain policy change.
Lines marked `effective` show the value in force; a domain GPO that sets the same policy overrides the local one.
`-SkipSsh` and `-SkipWinRM` leave those services alone, and `-MeshRange` changes the allowed source range.
The script backs up `Registry.pol` and `gpt.ini` beside the originals with a `.bak-<timestamp>` suffix before it writes them.

## Configure the Remmina profile

Precondition: the host passes `-Check`.

1. In the Remmina profile, set Colour depth to `GFX AVC444 (32 bpp)` and Network connection type to `Auto-detect`.

2. Connect once, then confirm on the host that the client negotiated AVC:

   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'; Id=162} -MaxEvents 1 | Format-List TimeCreated, Message
   ```

3. To watch the codec on songbird, set the profile's FreeRDP log filters to `com.freerdp.codec:DEBUG,com.freerdp.channels.rdpgfx.client:DEBUG`, quit any running Remmina, and start it from a terminal:

   ```sh
   remmina -c ~/.local/share/remmina/<profile>.remmina 2>&1 | grep -E 'RDPGFX_CODECID|accelerated H264'
   ```

Verification: event 162 reports `AVC available: 1`, and the terminal shows `RDPGFX_CODECID_AVC444` frames and `Using vaapi` for H.264 decoding once the screen changes.
Songbird decodes on its iGPU through the `intelDecodeDevice` option in `modules/apps/remmina.nix`.
Clear the log filters afterwards, since debug logging writes a line per frame.
