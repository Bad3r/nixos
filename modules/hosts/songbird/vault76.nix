# The SN720 volume vault76: LUKS2 over XFS, mounted at /srv/vault76.
# It has no snapshots and no second copy, so a deleted file is gone.
{
  configurations.nixos.songbird.module = {
    # Opens on demand only: noauto here and on the mount keeps it out of
    # cryptsetup.target and local-fs.target. Starting srv-vault76.mount pulls
    # in systemd-cryptsetup@vault76.service, which unlocks through an enrolled
    # YubiKey (FIDO2 PIN and touch) and asks for the passphrase when no
    # enrolled key shows up within token-timeout (30 s by default).
    environment.etc."crypttab".text = ''
      vault76 UUID=6746bf2b-3e77-405b-a74f-77baa6686ac3 none luks,discard,noauto,nofail,fido2-device=auto,timeout=120s,x-systemd.device-timeout=60s
    '';

    # discard trims a deleted file's blocks at once instead of at the weekly
    # fstrim, at the cost of slower deletes.
    fileSystems."/srv/vault76" = {
      device = "/dev/mapper/vault76";
      fsType = "xfs";
      options = [
        "noatime"
        "discard"
        "noauto"
        "nofail"
        "x-systemd.device-timeout=60s"
      ];
    };
  };
}
