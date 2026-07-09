# Safeguard RemoteApp: exporting files from the PAN-OS admin session

## Summary

Exporting a configuration or report from the Palo Alto (PAN-OS) web UI does
nothing when that UI runs inside a One Identity Safeguard RemoteApp session. A
Safeguard RemoteApp permits only the RDP channels needed to draw the published
window, so the session has no channel through which an exported file can leave
the remote host. The fix is server-side: the Safeguard administrator adds the
file-transfer channels (Disk redirect plus Sound, or Clipboard) to the channel
policy attached to this connection. The local RDP client cannot open a channel
that the Safeguard policy denies.

This document states the problem, the root cause, and the exact changes to
request, each backed by the official One Identity documentation.

## Environment

- Access path: local Remmina/FreeRDP client to a Safeguard for Privileged
  Sessions (SPS) proxy, which brokers an RDP RemoteApp on the firewall's jump
  host.
- Published RemoteApp: `OISGRemoteAppLauncher`, launching the PAN-OS
  administration UI for a Palo Alto firewall.
- The connection already works end to end. Only file export out of the session
  fails.

## Symptom

1. The Safeguard RemoteApp session opens the PAN-OS admin UI normally.
2. In PAN-OS, an export action is invoked, for example
   `Device > Setup > Operations > Export named configuration snapshot`, or a
   log/report export.
3. Clicking the export control produces no visible result: no Save As dialog,
   no downloaded file the operator can reach, no error.

## Root cause

The export is a file that the remote browser tries to write. The RemoteApp
browser runs on the jump host, so a download lands on the jump host disk, not on
the local workstation. Retrieving it requires an RDP channel that maps the local
drive into the session (`\\tsclient\...`) or that copies data out through the
clipboard.

One Identity Safeguard denies these channels by default for RemoteApp
connections. Per the official guidance, "RemoteApps use RDP channels that are
denied by default," and a working RemoteApp channel policy enables only:

- `Drawing` (mandatory; renders the published window), and
- `Custom` with the permitted channels `rail`, `rail_ri`, `rail_wi` (the
  RemoteApp seamless-window channels).

No `Disk redirect`, `Clipboard`, or `Sound` channel is present, so there is no
route for an exported file to leave the session. The export therefore has
nowhere to go and appears to do nothing.

## Requested changes (Safeguard administrator)

All changes are on the Safeguard/RDS side. The local client cannot enable a
channel that SPS strips.

### 1. Add file-transfer channels to the RemoteApp channel policy

In the SPS web interface:

1. Open `RDP Control > Connections` and note the `Channel policy` set on the
   connection that publishes the PAN-OS RemoteApp.
2. Open that policy under `RDP Control > Channel Policies`. It currently lists
   `Drawing` and `Custom` (`rail`, `rail_ri`, `rail_wi`). Keep both.
3. Add a channel with `Type = Sound`. This is a hard dependency: One Identity
   states that device redirections "work only if the Sound channel type is also
   enabled." Without it, disk redirection silently fails.
4. Add a channel with `Type = Disk redirect`. This maps the local client drive
   into the session as `\\tsclient\...`, so the PAN-OS Save As dialog can write
   the export back to the operator's machine.
   - Optional hardening: restrict the redirection with the `Permitted devices`
     field (for example a single drive letter) instead of allowing all drives.
5. Recommended for audit: enable `Record audit trail` on the redirect channel,
   and enable `Log file transfers to database` (and optionally
   `Log file transfers to syslog`) on the channel policy. Both logging options
   are off by default.
6. Save the channel policy. Confirm the connection under `RDP Control > Connections` still references it.

Text-only alternative: adding a `Clipboard` channel instead lets the operator
copy configuration text out of the session. Note that clipboard file copies are
not recorded in the audit logs or the File operations column, which is why
Safeguard disables the clipboard by default.

### 2. Adjust the RDS jump host

1. Disable the group policy `Use advanced RemoteFX graphics for RemoteApp`:
   `Computer Configuration > Policies > Administrative Templates > Windows Components > Remote Desktop Services > Remote Desktop Session Host > Remote Session Environment`. One Identity requires this for RemoteApp; leaving it
   enabled is a common reason that export dialogs or child windows do not render
   in seamless mode, which alone can make an export click appear to do nothing.
2. Ensure drive redirection is allowed on the RDS session collection (Client
   Settings: drives enabled).
3. Ensure the generated `.rdp` requests drives with the wildcard form
   `redirectdrives:i:1` and `drivestoredirect:s:*`. Specifying individual drive
   letters for a RemoteApp is documented as not working; use the wildcard.

## Verification

After the changes:

1. Reconnect and open the PAN-OS export action.
2. In the Save As dialog, the local drive should appear under `\\tsclient` (or a
   mapped drive letter). Save the export there; the file should then be present
   on the local workstation.

If the local drive is slow to appear under the `TSClient` node, map it to a
drive letter on the jump host with a short-delayed logon script
(`net use` after a few seconds), because drive redirection is not ready
immediately at session start.

## Alternatives that avoid RDP file transfer

If the administrator prefers not to open drive redirection, the configuration
can leave the firewall without any RDP channel:

- PAN-OS push off-box: from the firewall CLI, `scp export configuration to <user@host:/path>` or `tftp export configuration ...` sends the config
  directly to a destination the operator controls, bypassing the browser
  download entirely.
- PAN-OS XML API: `GET /api/?type=export&category=configuration&key=<APIKEY>`
  returns the running configuration as XML from a host that can reach the
  firewall management interface.

These move the file over the firewall's own network path rather than through the
RDP session, so the RemoteApp channel policy is not involved.

## Local client readiness

Once Safeguard permits `Disk redirect` plus `Sound`, the local client must also
request drive redirection for the mapping to appear:

- Remmina: enable the shared-folder / local-drive redirection option in the RDP
  profile.
- FreeRDP directly: `xfreerdp3 /drive:local,<path>` (and `+clipboard` if the
  clipboard channel is enabled).

This request is necessary but not sufficient: SPS strips any channel its policy
denies, so the client-side option has no effect until the server-side change in
section 1 is in place. The Safeguard-generated `.rdp` also controls redirection
flags, so the server side governs whether the client request survives.

## Security considerations

Safeguard denies drive redirection and clipboard for RemoteApp connections by
design, because both create a data-exfiltration path out of a privileged
session. Opening them is a policy decision for the Safeguard administrator, not
a client setting. Recommended scoping when granting the request:

- Restrict `Disk redirect` with `Permitted devices` rather than allowing all
  drives.
- Enable `Record audit trail` and `Log file transfers to database` so exports
  are attributable.
- Apply the change only to the specific connection policy used for PAN-OS
  administration, not to a shared policy.

## References

- One Identity Safeguard for Privileged Sessions 7.5, Supported RDP channel
  types (Disk redirect requires Sound; Custom for RemoteApp):
  <https://support.oneidentity.com/technical-documents/one-identity-safeguard-for-privileged-sessions/7.5/installation-guide/supported-rdp-channel-types>
- One Identity Safeguard for Privileged Sessions 7.0.2.1 LTS, Configuring
  RemoteApps (channels denied by default; Drawing plus Custom
  `rail`/`rail_ri`/`rail_wi`; disable the RemoteFX-for-RemoteApp group policy):
  <https://support.oneidentity.com/technical-documents/safeguard-for-privileged-sessions/7.0.2.1%20lts/administration-guide/rdp-specific-settings/configuring-remoteapps/>
- One Identity Safeguard for Privileged Sessions 7.3, Creating and editing
  channel policies (Clipboard, Disk redirect, Permitted devices, Log file
  transfers):
  <https://support.oneidentity.com/technical-documents/safeguard-for-privileged-sessions/7.3/administration-guide/68>
- One Identity Safeguard for Privileged Sessions 7.3, Configuring SPS to enable
  exporting files from audit trails after RDP file transfer through clipboard or
  disk redirection:
  <https://support.oneidentity.com/technical-documents/safeguard-for-privileged-sessions/7.3/administration-guide/rdp-specific-settings/configuring-sps-to-enable-exporting-files-from-audit-trails-after-rdp-file-transfer-through-clipboard-or-disk-redirection/>
