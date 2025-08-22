## Backup to a hosting service

Several companies offer [(paid) hosting services](https://www.borgbackup.org/support/commercial.html) for Borg repositories.

To backup your home directory to borgbase you have to:

- Generate a SSH key without a password, to access the remote server. E.g.

  ```programlisting
  sudo ssh-keygen -N '' -t ed25519 -f /run/keys/id_ed25519_borgbase
  ```

- Create the repository on the server by following the instructions for your hosting server.

- Initialize the repository on the server. Eg.

  ```programlisting
  sudo borg init --encryption=repokey-blake2  \
      --rsh "ssh -i /run/keys/id_ed25519_borgbase" \
      zzz2aaaaa@zzz2aaaaa.repo.borgbase.com:repo
  ```

- Add it to your NixOS configuration, e.g.

  ```programlisting
  {
      services.borgbackup.jobs = {
      my_Remote_Backup = {
          paths = [ "/" ];
          exclude = [ "/nix" "'**/.cache'" ];
          repo =  "zzz2aaaaa@zzz2aaaaa.repo.borgbase.com:repo";
            encryption = {
            mode = "repokey-blake2";
            passCommand = "cat /run/keys/borgbackup_passphrase";
          };
          environment = { BORG_RSH = "ssh -i /run/keys/id_ed25519_borgbase"; };
          compression = "auto,lzma";
          startAt = "daily";
      };
    };
  }}
  ```
