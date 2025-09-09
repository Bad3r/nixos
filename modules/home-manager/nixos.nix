{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos = {
    base = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        extraSpecialArgs.hasGlobalPkgs = true;
        backupFileExtension = "backup";

        users.${config.flake.meta.owner.username}.imports = [
          inputs.sops-nix.homeManagerModules.sops
          (
            { osConfig, ... }:
            {
              home.stateVersion = osConfig.system.stateVersion;
            }
          )
          config.flake.modules.homeManager.base
          # Wire R2 sops-managed env by default (guarded on secrets/r2.env presence)
          config.flake.modules.homeManager.r2Secrets
          # Optional HM roles (CLI and terminals)
          config.flake.modules.homeManager.roles.cli
          config.flake.modules.homeManager.roles.terminals
        ];
      };
    };

    pc = {
      home-manager.users.${config.flake.meta.owner.username}.imports = [
        config.flake.modules.homeManager.gui
      ];
    };
  };
}
