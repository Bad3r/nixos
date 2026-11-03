# RustDesk on Windows

A Windows device outside the NixOS hosts runs the RustDesk app against the fleet's own ID server over Cloudflare Mesh.
[rustdesk.md](rustdesk.md) covers the privacy model, the logins, and troubleshooting.
winget carries no RustDesk package, so the app comes from RustDesk's GitHub releases.

## Install and configure

Precondition: the device is connected to the Zero Trust team and reaches the Mesh.

1. On a NixOS host, from the repository root, print the PowerShell line that sets the server's Mesh address and public key.
   `<server>` is the host whose `modules/hosts/<host>/policy.nix` sets `rustdeskServer`.

   ```sh
   printf "\$server = '%s'; \$key = '%s'\n" \
     "$(getent hosts <server>.internal | awk '{print $1}')" \
     "$(sops -d --extract '["server_public_key"]' secrets/rustdesk.yaml)"
   ```

2. Open PowerShell as Administrator on the Windows device and paste that line.

3. Check that the server answers over the Mesh:

   ```powershell
   Test-NetConnection $server -Port 21116
   ```

   `TcpTestSucceeded : False` means the device is off the Mesh; reconnect WARP first.

4. Download the newest release's MSI, compare it with the SHA-256 digest GitHub records for it, and install it only on a match:

   ```powershell
   $ProgressPreference = 'SilentlyContinue'
   $arch = @{ AMD64 = 'x86_64'; ARM64 = 'aarch64' }[$env:PROCESSOR_ARCHITECTURE]
   $release = Invoke-RestMethod https://api.github.com/repos/rustdesk/rustdesk/releases/latest
   $asset = $release.assets | Where-Object name -Match "^rustdesk-[\d.]+-$arch\.msi$"
   $msi = Join-Path $env:TEMP $asset.name
   Invoke-WebRequest $asset.browser_download_url -OutFile $msi
   if ("sha256:$((Get-FileHash $msi -Algorithm SHA256).Hash)" -eq $asset.digest) {
     Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qb' -Wait
   } else { Write-Error "digest mismatch, not installed: $msi" }
   ```

5. Open RustDesk from the Start menu, then Settings, Network, Unlock network settings, and ID/Relay server.
   Enter the address from step 1 as the ID server and the key as the Key, leave Relay server and API server empty, and click OK.
   A `rustdesk.exe --option` change does not survive a service restart, so the dialog is the only setting path.

6. Restart the service and check that the server setting persisted:

   ```powershell
   Restart-Service RustDesk
   Select-String 'rendezvous|key' "$env:windir\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml"
   ```

   The lines show the server address and the key; `rs-ny.rustdesk.com` or another public server means the dialog change did not apply.

7. Reopen RustDesk, type a host's ID followed by `/r`, such as `<id>/r`, and connect with the fleet password, as in [Set up a non-NixOS device](rustdesk.md#set-up-a-non-nixos-device) step 3.
   The suffix forces the relay: a direct session from Windows ends in `Reset by the peer` without falling back to it.
   Type the ID, never the address, since a host refuses direct IP sessions.
   The suffix also saves Always connect via relay for that host, so later sessions from Recent sessions take the relay without it.

Verification: the status bar reads Ready with no prompt to set up a server, and a session's shield shows an encrypted connection.

## Let the hosts connect to the device

Precondition: the device runs RustDesk as installed above, and WARP connects at boot before a user signs in, which an enrolled device does unless multi-user mode is on.

1. In RustDesk on the device, open Settings, Security, and Unlock security settings, then:

   - under Password, choose Use permanent password and set one;
   - set Approve mode to Accept sessions via password;
   - turn on Use IP Whitelisting with the Mesh range that `nix eval --raw .#lib.nixos._cloudflareWarpMeshRange` prints on a host.

2. Keep the device awake on AC power, since a sleeping device leaves the Mesh:

   ```powershell
   powercfg /change standby-timeout-ac 0
   powercfg /change hibernate-timeout-ac 0
   ```

3. Print the salt RustDesk hashes the password with; the main window shows the ID:

   ```powershell
   Select-String '^salt' "$env:windir\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml"
   ```

4. On a host, from the repository root, add the device to the `peers` key as `secrets/rustdesk.yaml.example` shows, then push the secrets repository's `main`:

   ```sh
   sops secrets/rustdesk.yaml
   git -C secrets commit -am "chore: add <device> to the RustDesk peers"
   git -C secrets push origin HEAD:main
   ```

5. Commit the submodule bump and switch; the service writes the device into Favorites with its login and the relay forced.

Verification: the device appears by name under Favorites on each host, and a session opens without a password prompt, also at the Windows sign-in screen after a reboot.

## Upgrade

The app does not update through winget; run steps 2 and 4 again to install the newest release over the old one.

[RustDesk releases](https://github.com/rustdesk/rustdesk/releases)
