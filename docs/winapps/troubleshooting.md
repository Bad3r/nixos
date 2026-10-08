# WinApps troubleshooting

The `Outlook Classic` launcher hides FreeRDP's output, so a failed launch shows a notification or no window at all.
Most diagnostics repeat the connection from a terminal, where FreeRDP prints its errors.
Load the guest name, address, and account into the shell before a diagnostic:

```sh
. ~/.config/winapps/winapps.conf
```

## The menu entry opens no window

Cause: FreeRDP ended the connection at logon or at the certificate check, and the launcher hides its output.
Diagnostic, under `bash` because zsh does not word-split `$RDP_FLAGS`:

```sh
bash -c '. ~/.config/winapps/winapps.conf; FREERDP_ASKPASS="$RDP_ASKPASS" xfreerdp $RDP_FLAGS $RDP_FLAGS_NON_WINDOWS /d:"" /u:"$RDP_USER" /v:"$RDP_IP"'
```

Fix: a logon failure means the stored password is stale, so [renew it](operations.md#store-or-renew-the-rdp-password).
A certificate prompt means Windows regenerated its certificate, so answer `N` and repeat [the trust procedure](operations.md#trust-the-guest-certificate).

## Notification: RDP password unavailable

Cause: `packages/winapps-askpass` found the login keyring locked or the item missing.
Diagnostic:

```sh
secret-tool lookup service winapps account rdp | wc -c
```

Fix: a `0` means the item is missing or the keyring stayed locked; store the password again, or log out and back in so the login password unlocks the keyring.

## Notification: RDP port closed

Cause: the guest firewall blocks the port, Remote Desktop is off, or Windows is still booting.
Diagnostic:

```sh
virsh domstate "$VM_NAME" --reason
nc -zv "$RDP_IP" 3389
```

Fix: when the port stays closed on a running guest, repeat [Enable RemoteApp in the guest](remoteapp-setup.md#enable-remoteapp-in-the-guest); when the guest was still booting, relaunch.

## Notification: timeout waiting for Windows

Cause: the launcher booted the guest, and the RDP port stayed closed for longer than the launcher waits.
Diagnostic:

```sh
virsh domstate "$VM_NAME" --reason
nc -zv "$RDP_IP" 3389
```

Fix: relaunch once the port answers, since the guest keeps booting after the launcher gives up; a port that stays closed has its fix under [RDP port closed](#notification-rdp-port-closed).

## Notification: the Windows VM does not exist

Cause: `virsh` is missing from `PATH`, which the launcher reports as a missing domain; a configuration whose `VM_NAME` differs from the declared guest gives the same message.
Diagnostic:

```sh
command -v virsh
virsh list --all --name
```

Fix: `virsh` comes from `virtualisation.libvirtd`, which the guest module enables; run the launcher from a session that has the system profile on `PATH`.

## A popup or menu freezes the window

Cause: FreeRDP's RemoteApp popup handling can stall the session.
Diagnostic: the window ignores input while `virsh domstate "$VM_NAME"` still prints `running`.
Fix: end the session and relaunch:

```sh
winapps killrdp
```

Contingency: run Outlook inside the full desktop from `winapps windows`, where popups are ordinary windows.

## No tray icon and no new-mail toast

Cause: RemoteApp forwards application windows only.
Diagnostic: new mail plays the chime that the session's sound redirection carries, while no toast appears.
Fix: in Outlook, add a rule that displays a message in the New Item Alert window, which RemoteApp forwards.

## All Outlook windows share one window class

Cause: FreeRDP gives every RemoteApp window the class from `/wm-class`.
Diagnostic:

```sh
xprop WM_CLASS WM_NAME
```

Fix: match i3 rules on `title` instead of `class`.

## Text is too small or too large

Cause: `RDP_SCALE` sets the scale, and the launcher accepts 100, 140, and 180 only, snapping any other value to the nearest.
Diagnostic: `rg RDP_SCALE ~/.config/winapps/winapps.conf` prints the value in effect.
Fix: change `RDP_SCALE` in `modules/hm-apps/winapps.nix` and run `./build.sh`.

## The guest clock is wrong after resume

Cause: the resume hook sets the clock through the guest agent, which was stopped or slow to answer.
Diagnostic:

```sh
virsh domtime "$VM_NAME" --pretty
virsh qemu-agent-command "$VM_NAME" '{"execute":"guest-ping"}'
journalctl -b -u sleep-actions
```

Fix: start the `QEMU Guest Agent` service in the guest, then run `virsh domtime "$VM_NAME" --now`.

## Notification: Windows failed to resume

Cause: Windows entered sleep, which libvirt reports as `pmsuspended`, and the `virsh resume` the launcher runs cannot wake that state.
Diagnostic: `virsh domstate "$VM_NAME" --reason` prints `pmsuspended`.
Fix: wake the guest, then turn sleep off in it as in [provisioning.md](provisioning.md#configure-windows):

```sh
virsh dompmwakeup "$VM_NAME"
```

## The transfer folder is missing in Windows

Cause: the session shares `~/Documents/Outlook-Transfer` as `\\tsclient\transfer` only when the directory exists at launch.
Diagnostic:

```sh
stat -c %a ~/Documents/Outlook-Transfer
```

In the guest, `net view \\tsclient` lists the shares the session carries.
Fix: create the directory with `mkdir -m 700 ~/Documents/Outlook-Transfer`, which the Home Manager activation step also does at every switch, then relaunch.

Sources: [FreeRDP RAIL popup freeze](https://github.com/FreeRDP/FreeRDP/issues/12453), [WinApps Office RAIL freeze](https://github.com/winapps-org/winapps/issues/953), [WinApps tray icons](https://github.com/winapps-org/winapps/issues/34), [WinApps shared WM_CLASS](https://github.com/winapps-org/winapps/issues/267).
