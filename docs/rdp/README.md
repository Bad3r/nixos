# RDP

Operator documentation for Remote Desktop (RDP) access that this workstation
uses through One Identity Safeguard for Privileged Sessions (SPS). The local
client is Remmina (with FreeRDP), configured under `modules/apps/remmina.nix`
and `modules/hm-apps/remmina.nix`; the remote side is a Safeguard-brokered
RemoteApp published by the target firewall's jump host.

## Scope

- Safeguard RemoteApp session behavior that the local client cannot change on
  its own, because SPS enforces it at the proxy.
- Administrator change requests to send to the Safeguard/RDS operator, with the
  official One Identity documentation that backs each request.

## Contents

| Document                                                                 | Purpose                                                                                               |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| [safeguard-remoteapp-file-export.md](safeguard-remoteapp-file-export.md) | Why file export/download fails inside a Safeguard RemoteApp session, and the exact changes to request |

## Related repository files

- `modules/apps/remmina.nix`: system-level Remmina client and the
  `application/x-rdp` MIME package.
- `modules/hm-apps/remmina.nix`: Home Manager Remmina integration.
- `modules/xdg/mime.nix`: routes `.rdp` profile files to Remmina.

## Upstream documentation

- One Identity Safeguard for Privileged Sessions Administration Guide:
  <https://support.oneidentity.com/technical-documents/one-identity-safeguard-for-privileged-sessions>
