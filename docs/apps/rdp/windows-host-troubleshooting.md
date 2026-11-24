# Windows RDP host troubleshooting

Failures seen on Windows hosts configured by `scripts/windows/rdp-host-setup.ps1`.
The setup procedure is [windows-host-setup.md](windows-host-setup.md).

## AVC444 session drops seconds after connecting

Remmina reconnects in a loop, and FreeRDP logs `Unhandled SSL error ... decode error` and `ERRCONNECT_CONNECT_TRANSPORT_FAILED`, while AVC420 and non-GFX connections stay up.
Cause: with Configure H.264/AVC hardware encoding enabled, the server's AVC444 encoder fails with `0x80070057` and the server drops the connection.
Diagnose on the host:

```powershell
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'; Id=226,97} -MaxEvents 6 | Format-List TimeCreated, Id, Message
```

Event 226 names `PipeStateEncoding` with `0x80070057`, followed by event 97 with error 303.
Fix: run the script, which sets the policy to Disabled, then reconnect.

## Session never uses H.264

The FreeRDP codec log shows only `RDPGFX_CODECID_PLANAR` and `RDPGFX_CODECID_UNCOMPRESSED`, never `AVC420` or `AVC444`.
Cause: Configure image quality for RemoteFX Adaptive Graphics set to Lossless restricts the server to lossless codecs.
Diagnose on the host; `1` means Lossless:

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services').ImageQuality
```

Fix: run the script, which sets High, then reconnect.
Remmina's `Auto-detect` network type advertises AVC444 whatever the colour depth says, so a client-side colour depth change alone does not avoid AVC444.

## SSH over the Mesh fails with "No route to host"

Cause: sshd is stopped, or the OpenSSH firewall rule covers only the Private profile while Windows files the CloudflareWARP adapter under Public.
Diagnose on the host:

```powershell
Get-Service sshd | Format-List Status, StartType
Get-NetConnectionProfile | Format-Table InterfaceAlias, NetworkCategory
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP | Format-List Enabled, Profile
```

Fix: run the script, which starts sshd with Automatic startup and opens port 22 on every profile for the Mesh range only.

## OpenSSH Server is missing from Optional features

Settings may list only the OpenSSH client.
Fix: the script installs the server capability; the manual command is:

```powershell
Add-WindowsCapability -Online -Name (Get-WindowsCapability -Online -Name 'OpenSSH.Server*').Name
```

## SSH key login fails for an administrator

Cause: sshd reads keys for members of Administrators from `C:\ProgramData\ssh\administrators_authorized_keys`, never from the user's `.ssh\authorized_keys`, and ignores that file unless only Administrators and SYSTEM hold rights on it.
A key generated on the Windows host plays no part in logging in to it.
Fix: pass the client's public key to the script with `-AuthorizedKey`, which appends it and resets the file's permissions.

## gpupdate reports that computer policy failed

Cause: `gpupdate` reports failure when domain policy processing fails, for example a SYSVOL read error (System event 1030 or 1058), even when local policy applied.
Diagnose: `.\rdp-host-setup.ps1 -Check` shows whether the `effective` values match.
Fix: local settings need no action; domain policy errors belong to the domain administrators.
