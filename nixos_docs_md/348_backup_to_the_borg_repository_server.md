## Backup to the borg repository server

The following NixOS snippet creates an hourly backup to the service (on the host nixos) as created in the section above. We assume that you have stored a secret passphrasse in the file `/run/keys/borgbackup_passphrase`, which should be only accessible by root

```programlisting
{
  services.borgbackup.jobs = {
    backupToLocalServer = {
      paths = [ "/etc/nixos" ];
      doInit = true;
      repo = "borg@nixos:.";
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat /run/keys/borgbackup_passphrase";
      };
      environment = {
        BORG_RSH = "ssh -i /run/keys/id_ed25519_my_borg_repo";
      };
      compression = "auto,lzma";
      startAt = "hourly";
    };
  };
}
```

The following few commands (run as root) let you test your backup.

```programlisting
> nixos-rebuild switch
...restarting the following units: polkit.service
> systemctl restart borgbackup-job-backupToLocalServer
> sleep 10
> systemctl restart borgbackup-job-backupToLocalServer
> export BORG_PASSPHRASE=topSecret
> borg list --rsh='ssh -i /run/keys/id_ed25519_my_borg_repo' borg@nixos:.
nixos-backupToLocalServer-2020-03-30T21:46:17 Mon, 2020-03-30 21:46:19 [84feb97710954931ca384182f5f3cb90665f35cef214760abd7350fb064786ac]
nixos-backupToLocalServer-2020-03-30T21:46:30 Mon, 2020-03-30 21:46:32 [e77321694ecd160ca2228611747c6ad1be177d6e0d894538898de7a2621b6e68]
```
