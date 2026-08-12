{ lib, ... }:
let
  InsecurePackages =
    { config, ... }:
    {
      options.nixpkgs.extraPermittedInsecurePackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional insecure package names permitted for this NixOS host.";
      };

      config.nixpkgs.config.permittedInsecurePackages = config.nixpkgs.extraPermittedInsecurePackages;
    };
in
{
  # The host constructor imports this module before the shareCommon branch so
  # standalone hosts can use app modules with this policy option.
  flake.nixosModules.nixpkgs-allowed-insecure = InsecurePackages;
}
