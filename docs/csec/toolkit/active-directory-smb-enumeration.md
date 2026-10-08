# Pentesting Toolkit: Active Directory & SMB Enumeration

[Back to Pentesting Toolkit](../toolkit.md)

## Active Directory & SMB Enumeration

- netexec
  - run..: `nxc smb $target -u $user -p $pass`
  - Repo.: <https://github.com/Pennyw0rth/NetExec>
  - Docs.: <https://www.netexec.wiki/>
  - Desc.: Maintained CrackMapExec fork for SMB/WinRM/MSSQL/LDAP/SSH/RDP/FTP/NFS/VNC/WMI enumeration and authenticated testing. The nixpkgs package is `netexec`; the installed executable is `nxc`.
- samba
  - run..: `smbclient -L $target -U $user`; `nmblookup -A $target`; `rpcclient $target -U $user`
  - Repo.: <https://gitlab.com/samba-team/samba>
  - Docs.: <https://www.samba.org/samba/docs/>
  - Desc.: SMB/CIFS client suite providing share access through `smbclient`, NetBIOS name and address queries through `nmblookup`, and MS-RPC enumeration through `rpcclient`.
- smbmap
  - run..: `smbmap -H $target -u $user -p $pass`
  - Repo.: <https://github.com/ShawnDEvans/smbmap>
  - Docs.: <https://github.com/ShawnDEvans/smbmap#readme>
  - Desc.: Enumerates SMB shares and permissions with recursive listing, file search, transfer, and remote command features.
