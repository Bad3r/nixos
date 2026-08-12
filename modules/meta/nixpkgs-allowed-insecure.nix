{ lib, ... }:
{
  flake.nixosModules.base =
    { config, ... }:
    {
      options.nixpkgs.extraPermittedInsecurePackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional insecure package names permitted for this NixOS host.";
      };

      config.nixpkgs.config.permittedInsecurePackages = config.nixpkgs.extraPermittedInsecurePackages;
    };
}
