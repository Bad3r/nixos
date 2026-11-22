# RDP

Operator documentation for Remote Desktop (RDP) access from this workstation.
The local client is Remmina (with FreeRDP), configured under
`modules/apps/remmina.nix`. Targets are Windows hosts reached over the
Cloudflare WARP Mesh, and Safeguard-brokered RemoteApps published by One
Identity Safeguard for Privileged Sessions (SPS).

## Scope

- Preparing a Windows host as an AVC444 RDP, SSH, and WinRM target, and its
  known failures.
- Safeguard RemoteApp session behavior that the local client cannot change on
  its own, because SPS enforces it at the proxy.
- Administrator change requests to send to the Safeguard/RDS operator, with the
  official One Identity documentation that backs each request.

## Contents

| Document                                                                 | Purpose                                                                                               |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| [windows-host-setup.md](windows-host-setup.md)                           | Configure a Windows host and the Remmina profile for AVC444 RDP                                       |
| [windows-host-troubleshooting.md](windows-host-troubleshooting.md)       | Known failures on those hosts: AVC444 drops, no H.264, SSH over the Mesh                              |
| [safeguard-remoteapp-file-export.md](safeguard-remoteapp-file-export.md) | Why file export/download fails inside a Safeguard RemoteApp session, and the exact changes to request |

## Related repository files

- `modules/apps/remmina.nix`: system-level Remmina client, the
  `application/x-rdp` MIME package, and the optional Intel render node for
  hardware H.264 decoding (`intelDecodeDevice`).
- `modules/xdg/mime.nix`: routes `.rdp` profile files to Remmina.
- `scripts/windows/rdp-host-setup.ps1`: applies and checks the Windows host
  settings.

## Upstream documentation

- One Identity Safeguard for Privileged Sessions Administration Guide:
  <https://support.oneidentity.com/technical-documents/one-identity-safeguard-for-privileged-sessions>
