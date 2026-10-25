_:
let
  body =
    {
      config,
      lib,
      ...
    }:
    {
      # libata refuses ATA TRUSTED SEND/RECEIVE unless this is set, which is the
      # only path Opal traffic takes to a SATA drive. Keep the host-wide
      # relaxation tied to its optional sedutil consumer. NVMe goes through
      # admin security send/receive instead and is unaffected.
      boot.kernelParams = lib.mkIf config.programs.sedutil.extended.enable [ "libata.allow_tpm=1" ];
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
