/*
  Package: hydra
  Description: Parallelized network login cracker supporting numerous protocols.
  Homepage: https://github.com/vanhauser-thc/thc-hydra
  Documentation: https://github.com/vanhauser-thc/thc-hydra#usage
  Repository: https://github.com/vanhauser-thc/thc-hydra

  Summary:
    * Performs fast brute-force and dictionary attacks against common services (SSH, FTP, HTTP, databases, etc.).
    * Supports custom module development and numerous input/output formats for automation.

  Options:
    hydra -L users.txt -P passwords.txt ssh://host: Attack SSH with username and password lists.
    hydra -C creds.txt http-get-form "/login:username=^USER^&password=^PASS^:F=failed": Test web form authentication.
    hydra -R: Resume a previous session from the `hydra.restore` file.
*/
_:
let
  HydraModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.hydra.extended;
    in
    {
      options.programs.hydra.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable hydra.";
        };

        package = lib.mkPackageOption pkgs "thc-hydra" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.hydra = HydraModule;
}
