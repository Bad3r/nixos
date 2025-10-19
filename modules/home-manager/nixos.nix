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

      options.home-manager.extraAppImports = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional Home Manager app keys appended to the default app list.";
      };

      config.home-manager = {
        useGlobalPkgs = true;
        extraSpecialArgs = {
          hasGlobalPkgs = true;
          inherit inputs;
        };
        backupFileExtension = "hm.bk";

        users.${
          let
            flakeAttrs = config.flake or { };
            ownerMeta = lib.attrByPath [ "lib" "meta" "owner" ] { } flakeAttrs;
            fallbackOwnerName =
              let
                usersAttrs = config.users.users or { };
                normalUsers = lib.filterAttrs (_: u: (u.isNormalUser or false)) usersAttrs;
              in
              if normalUsers != { } then lib.head (lib.attrNames normalUsers) else null;
          in
          ownerMeta.username or (
            if fallbackOwnerName != null then
              fallbackOwnerName
            else
              throw "Home Manager base module: unable to determine owner username (set config.flake.lib.meta.owner.username or define a normal user)."
          )
        }.imports =
          let
            moduleArgs = config._module.args or { };
            inputsArg = moduleArgs.inputs or { };
            flakeAttrs = config.flake or { };
            hmModulesFromConfig = lib.attrByPath [ "homeManagerModules" ] { } flakeAttrs;
            hmModulesFromInputs = lib.attrByPath [ "self" "homeManagerModules" ] { } inputsArg;
            hmModules = if hmModulesFromConfig != { } then hmModulesFromConfig else hmModulesFromInputs;
            hmApps = hmModules.apps or { };
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
              "ghq-mirror"
              "kitty"
              "alacritty"
              "wezterm"
            ];
            extraAppImports = lib.attrByPath [ "home-manager" "extraAppImports" ] [ ] config;
            allAppImports = defaultAppImports ++ extraAppImports;
          in
          [
            inputs.sops-nix.homeManagerModules.sops
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.stateVersion;
              }
            )
            (lib.attrByPath [ "base" ] hmModules (
              throw "Home Manager base module: expected flake.homeManagerModules.base to be available."
            ))
            # Wire R2 sops-managed env by default (guarded on secrets/r2.env presence)
            (lib.attrByPath [ "r2Secrets" ] hmModules { })
            # Provide Context7 API key via sops when available
            (lib.attrByPath [ "context7Secrets" ] hmModules { })
          ]
          ++ map getApp allAppImports;
      };
    };
  };
}
