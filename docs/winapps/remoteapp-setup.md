# WinApps RemoteApp setup

RemoteApp presents one Windows program as its own window over RDP, and the guest allows it only after a registry import and a firewall change.
Commands run in an elevated PowerShell in the guest, signed in as the account that `host.virtualization.windowsGuest.rdpUser` names, unless a step names the host.

## Enable RemoteApp in the guest

Precondition: Windows, the guest tools, the updates, and the Windows applications are installed, and a [baseline](storage.md#record-a-baseline) exists.

1. On the host, from the repository root, read the locked WinApps revision and the host address on the guest bridge:

   ```sh
   jq -r '.nodes.winapps.locked.rev' flake.lock
   ip -4 -br addr show virbr-winapps
   ```

2. In the guest, import the registry file of that revision; it turns Remote Desktop on with NLA and lets unlisted programs run as RemoteApps:

   ```powershell
   Invoke-WebRequest "https://raw.githubusercontent.com/winapps-org/winapps/<revision>/oem/RDPApps.reg" -OutFile "$env:TEMP\RDPApps.reg"
   reg import "$env:TEMP\RDPApps.reg"
   ```

   The upstream installer script is skipped, because the clock task it registers needs a home-directory share.

3. Open the Remote Desktop firewall group and scope it to the host address from step 1, without the prefix length:

   ```powershell
   Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
   Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -RemoteAddress <host-bridge-address>
   ```

4. Restart the guest.

Verification: on the host, after `. ~/.config/winapps/winapps.conf`, `nc -zv "$RDP_IP" 3389` reports success, and in the guest `Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Get-NetFirewallAddressFilter` lists the host address as the only remote address.

## Confirm the Outlook path

Precondition: Office is installed in the guest.

1. In the guest, print the registered path of the Outlook executable:

   ```powershell
   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE').'(default)'
   ```

2. Compare it with `outlookExe` in `modules/hm-apps/winapps.nix`.
   Windows paths ignore letter case, so only a path that differs beyond case replaces the constant, followed by `./build.sh`.

Verification: the printed path and `outlookExe` match apart from letter case.

Sources: [WinApps RDPApps.reg](https://github.com/winapps-org/winapps/blob/main/oem/RDPApps.reg).
