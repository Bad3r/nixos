# The SN720 volume vault76: LUKS2 over XFS, mounted at /srv/vault76.
# It has no snapshots and no second copy, so a deleted file is gone.
{
  configurations.nixos.songbird.module = {
    # Stage 2, after root: the keyfile lives on the encrypted root, which the
    # initrd cannot read. The "-" key field loads
    # /etc/cryptsetup-keys.d/vault76.key and falls back to a passphrase prompt
    # bounded by timeout= when that file is missing.
    environment.etc."crypttab".text = ''
      vault76 UUID=6746bf2b-3e77-405b-a74f-77baa6686ac3 - luks,discard,nofail,timeout=120s,x-systemd.device-timeout=60s
    '';

    # discard trims a deleted file's blocks at once instead of at the weekly
    # fstrim, at the cost of slower deletes.
    fileSystems."/srv/vault76" = {
      device = "/dev/mapper/vault76";
      fsType = "xfs";
      options = [
        "noatime"
        "discard"
        "nofail"
        "x-systemd.device-timeout=60s"
      ];
    };
  };
}
