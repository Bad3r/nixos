## Create a borg backup server

You should use a different SSH key for each repository you write to, because the specified keys are restricted to running borg serve and can only access this single repository. You need the output of the generate pub file.

```programlisting

# sudo ssh-keygen -N '' -t ed25519 -f /run/keys/id_ed25519_my_borg_repo

# cat /run/keys/id_ed25519_my_borg_repo

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID78zmOyA+5uPG4Ot0hfAy+sLDPU1L4AiIoRYEIVbbQ/ root@nixos
```

Add the following snippet to your NixOS configuration:

```programlisting
{
  services.borgbackup.repos = {
    my_borg_repo = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID78zmOyA+5uPG4Ot0hfAy+sLDPU1L4AiIoRYEIVbbQ/ root@nixos"
      ];
      path = "/var/lib/my_borg_repo";
    };
  };
}
```
