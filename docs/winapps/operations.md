# WinApps Outlook Classic operations

`modules/apps/winapps.nix` installs the WinApps launcher.
`modules/hm-apps/winapps.nix` writes its configuration, the `Outlook Classic` menu entry, and the transfer directory the session shares with the guest.
The RDP password lives in the login keyring, where `packages/winapps-askpass` reads it for FreeRDP, so it sits in no file and on no command line.
Load the guest name, address, account, and askpass command into the shell before a procedure:

```sh
. ~/.config/winapps/winapps.conf
```

## Store or renew the RDP password

Precondition: the guest account that `host.virtualization.windowsGuest.rdpUser` names has a password, and the login keyring is unlocked, which the graphical login does.
An expired Windows password is changed at the guest console first, because NLA cannot change it.

1. Store the password; the prompt reads it from the terminal, so it reaches neither the argument list nor the shell history:

   ```sh
   secret-tool store --label='WinApps RDP password' service winapps account rdp
   ```

Verification: `secret-tool lookup service winapps account rdp | wc -c` prints the length of the stored password.

## Trust the guest certificate

Precondition: the guest is running, [RemoteApp setup](remoteapp-setup.md) is complete, and the password is stored.
FreeRDP accepts a stored certificate silently and asks on the terminal before it trusts any other one.
The launcher starts FreeRDP with no input to answer that question, so a launch refuses a new certificate.
Windows regenerates the certificate when it expires, so the procedure repeats then.

1. At the guest console, in an elevated PowerShell, print the fingerprint in the form FreeRDP shows:

   ```powershell
   ((Get-ChildItem 'Cert:\LocalMachine\Remote Desktop').GetCertHashString('SHA256') -replace '(..)(?!$)','$1:').ToLower()
   ```

2. Remove the stored entry for the guest:

   ```sh
   rm -f ~/.config/freerdp/server/"$RDP_IP"_3389.pem
   ```

3. Connect from a terminal, compare the fingerprint, and answer `Y`:

   ```sh
   FREERDP_ASKPASS="$RDP_ASKPASS" xfreerdp /d:"" /u:"$RDP_USER" /v:"$RDP_IP"
   ```

   The session shares no drive, and the desktop window can close as soon as it appears.

Verification: `openssl x509 -in ~/.config/freerdp/server/"$RDP_IP"_3389.pem -noout -fingerprint -sha256` prints the hex pairs from step 1 in upper case.

## Start Outlook Classic

Precondition: the password is stored and the certificate is trusted.

1. Pick `Outlook Classic` in the application launcher.
   The launcher starts the guest when it is shut off, waits for the RDP port, and reports each stage through a notification.
2. Keep `Hide When Minimized` off in the Outlook tray settings, since RemoteApp forwards windows and no tray icon.
   Outlook syncs mail only while it runs, and closing its main window exits it.

Verification: `xprop WM_CLASS` on the Outlook window prints the class that `RDP_FLAGS_NON_WINDOWS` sets, and `virsh domstate "$VM_NAME"` prints `running`.

## Open the full desktop

Precondition: the password is stored and the certificate is trusted.

1. Start a desktop session:

   ```sh
   winapps windows
   ```

Verification: a `Windows RDP Session` window opens, and Outlook windows that were open move into it, since RemoteApp and the desktop share one Windows session.

## Check the launcher boundary

Precondition: an Outlook Classic window is open.
The `winapps` input moves with the daily lock update, so the check runs after each bump.

1. Read the FreeRDP argument list and the askpass variables of its environment:

   ```sh
   tr '\0' '\n' < /proc/"$(pgrep -n xfreerdp)"/cmdline | rg '^(/drive|\+home-drive|/drives|\+drives|/p:|/cert)'
   tr '\0' '\n' < /proc/"$(pgrep -n xfreerdp)"/environ | rg '^(FREERDP_ASKPASS|RDP_PASS)='
   ```

2. Search the launcher artifacts for the stored password without placing it on a command line:

   ```sh
   rg -F -c -f <(secret-tool lookup service winapps account rdp) ~/.config/winapps/winapps.conf ~/.local/share/winapps/winapps.log "$RDP_ASKPASS" /etc/profiles/per-user/"$USER"/share/applications/outlook-classic.desktop
   ```

Verification: step 1 prints one `/drive:` line naming the transfer directory and one `FREERDP_ASKPASS=` line, and step 2 prints nothing and exits 1.

## Shut Windows down

Precondition: Outlook is closed.

1. Send the shutdown request and wait for `shut off`:

   ```sh
   virsh shutdown "$VM_NAME"
   virsh domstate "$VM_NAME"
   ```

Verification: `virsh domstate "$VM_NAME"` prints `shut off`.

## Apply Windows and Office updates

Precondition: Outlook is closed, and no host shutdown is due within the hour, since the host powers the guest off once the libvirt shutdown timeout passes.

1. Open the full desktop with `winapps windows`.
2. Run Windows Update until it offers nothing more, then in any Office application pick `File`, `Account`, `Update Options`, `Update Now`.
3. Restart the guest from the Start menu.
4. Start Outlook Classic from the menu.

Verification: Windows Update reports the guest up to date, and Outlook opens from the menu.

## Discontinue

Precondition: the guest is shut off.

1. Clear the keyring item, the launcher state, and the stored certificate while the configuration file still names the guest:

   ```sh
   secret-tool clear service winapps account rdp
   rm -r ~/.local/share/winapps
   rm -f ~/.config/freerdp/server/"$RDP_IP"_3389.pem
   ```

2. Remove the `freerdp`, `libsecret`, and `winapps` entries from `modules/tpnix/apps-enable.nix` and `"winapps"` from `extraHomeApps` in `modules/tpnix/policy.nix`, then run `./build.sh`.
   The guest declaration and its disk stay in place; disposing of them follows the [rules that prevent data loss](README.md#rules-that-prevent-data-loss).

Verification: `~/.config/winapps` is gone, and `Outlook Classic` is absent from the application launcher.

Sources: [FreeRDP global environment variables](https://github.com/FreeRDP/FreeRDP/blob/master/client/common/man/freerdp-global-envvar.1.in).
