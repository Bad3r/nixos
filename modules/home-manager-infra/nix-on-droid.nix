# Module: home-manager-infra/nix-on-droid.nix
# Purpose: Home Manager user environment configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment
# Dependencies: config.flake.modules.homeManager.base ],

{
  config,
  ...
}:
{
  flake.modules.nixOnDroid.base = args: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs.hasGlobalPkgs = true;
      config = {
        home.stateVersion = args.config.system.stateVersion;
        imports = [ config.flake.modules.homeManager.base ];
      };
    };
  };
}
