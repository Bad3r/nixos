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
            hmApps = config.flake.homeManagerModules.apps or { };
            hasApp = name: lib.hasAttr name hmApps;
            getApp =
              name:
              if hasApp name then
                lib.getAttr name hmApps
              else
                throw "Unknown Home Manager app '${name}' referenced by base imports";
            defaultAppImports = [
              "codex"
              "bat"
              "eza"
              "fzf"
              "kitty"
              "alacritty"
              "wezterm"
            ];
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
          ++ map getApp defaultAppImports;
      };
    };

    pc = {
      home-manager.users.${config.flake.lib.meta.owner.username}.imports = [
        config.flake.homeManagerModules.gui
      ];
    };
  };
}
