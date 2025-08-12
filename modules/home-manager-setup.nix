# Note: This module sets up Home-Manager for the system

{
  config,
  inputs,
  lib,
  ...
}:
{
  # Home Manager is fundamental infrastructure needed by all systems
  # Therefore it extends base, not creates a named module
  flake.modules.nixos.base = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    home-manager = {
      useGlobalPkgs = true;
      extraSpecialArgs.hasGlobalPkgs = true;
      # https://github.com/nix-community/home-manager/issues/6770
      #useUserPackages = true;

      # Configure user with appropriate modules based on system type
      users.${config.flake.meta.owner.username}.imports = 
        let
          baseImports = [
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.stateVersion;
              }
            )
            config.flake.modules.homeManager.base
          ];
          # Check if this is a desktop system (has desktop in imports)
          # For now, always include both base and gui
          allImports = baseImports ++ [ config.flake.modules.homeManager.gui ];
        in
          allImports;
    };
  };
}