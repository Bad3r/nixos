{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.nixosModules = {
    base = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = true;
        extraSpecialArgs.hasGlobalPkgs = true;
        backupFileExtension = ".hm.bk";

        users.${config.flake.lib.meta.owner.username}.imports =
          let
            roles = config.flake.lib.homeManager.roles or { };
            hasApp = name: lib.hasAttrByPath [ "apps" name ] config.flake.homeManagerModules;
            getApp =
              name:
              if hasApp name then
                lib.getAttrFromPath [ "apps" name ] config.flake.homeManagerModules
              else
                throw "Unknown Home Manager app '${name}' referenced by roles";
            roleToModules = roleName: map getApp (roles.${roleName} or [ ]);
          in
          [
            inputs.sops-nix.homeManagerModules.sops
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.stateVersion;
              }
            )
            config.flake.homeManagerModules.base
            # Wire R2 sops-managed env by default (guarded on secrets/r2.env presence)
            config.flake.homeManagerModules.r2Secrets
            # Provide Context7 API key via sops when available
            config.flake.homeManagerModules.context7Secrets
          ]
          # Resolve role specs (data) to concrete HM app modules at the glue layer
          ++ (roleToModules "cli")
          ++ (roleToModules "terminals");
      };
    };

    pc = {
      home-manager.users.${config.flake.lib.meta.owner.username}.imports = [
        config.flake.homeManagerModules.gui
      ];
    };
  };
}
