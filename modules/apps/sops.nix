/*
  Package: sops
  Description: Simple and flexible tool for managing secrets.
  Homepage: https://getsops.io/
  Documentation: https://getsops.io/

  Summary:
    * Encrypts and decrypts structured secret files while preserving readable key structure.
    * Supports Age, PGP, KMS, and cloud key backends for team-managed secret workflows.

  Options:
    -e: Encrypt a plaintext file to standard output.
    -d: Decrypt an encrypted file to standard output.
    updatekeys: Reconcile the file with the current key groups in `.sops.yaml`.
*/
_:
let
  SopsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sops.extended;
    in
    {
      options.programs.sops.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sops.";
        };

        package = lib.mkPackageOption pkgs "sops" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sops = SopsModule;
}
