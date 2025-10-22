{
  config,
  inputs,
  lib,
  ...
}:
builtins.trace "hm.nixos entry" {
  flake.nixosModules = {
    base = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      options.home-manager.extraAppImports = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional Home Manager app keys appended to the default app list.";
      };

      config.home-manager =
        let
          flakeAttrs = config.flake or { };
          ownerMeta = lib.attrByPath [ "lib" "meta" "owner" ] { } flakeAttrs;
          usersAttrs = config.users.users or { };
          normalUsers = lib.filterAttrs (_: u: (u.isNormalUser or false)) usersAttrs;
          ownerName =
            ownerMeta.username or (
              if normalUsers != { } then
                lib.head (lib.attrNames normalUsers)
              else
                throw "Home Manager base module: unable to determine owner username (set config.flake.lib.meta.owner.username or define a normal user)."
            );
          moduleArgs = config._module.args or { };
          inputsArg = moduleArgs.inputs or { };
          hmModulesFromConfig = lib.attrByPath [ "homeManagerModules" ] { } flakeAttrs;
          hmModulesFromInputs = lib.attrByPath [ "self" "homeManagerModules" ] { } inputsArg;
          hmModules =
            let
              combined =
                assert (
                  lib.hasAttrByPath [ "homeManagerModules" "base" ] flakeAttrs
                  || lib.hasAttrByPath [ "self" "homeManagerModules" "base" ] inputsArg
                );
                if hmModulesFromConfig != { } then hmModulesFromConfig else hmModulesFromInputs;
            in
            builtins.trace (
              "hm.nixos hmModules keys: "
              + (if combined != { } then lib.concatStringsSep ", " (lib.attrNames combined) else "<empty>")
            ) combined;
          configBase = lib.attrByPath [ "base" ] hmModules null;
          baseModuleImports =
            if configBase == null then
              throw "Home Manager base module: expected flake.homeManagerModules.base to be available."
            else if configBase ? imports then
              configBase.imports
            else if configBase ? content && configBase.content ? imports then
              configBase.content.imports
            else
              [ configBase ];
          hmApps = hmModules.apps or { };
          _hmAppsTrace = builtins.trace (
            "hm.nixos hmApps: " + (if hmApps == null then "null" else builtins.typeOf hmApps)
          ) null;
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
          appModulesRaw = map getApp allAppImports;
          guiModule = lib.attrByPath [ "gui" ] hmModules null;
          context7SecretsModule = lib.attrByPath [ "context7Secrets" ] hmModules null;
          r2SecretsModule = lib.attrByPath [ "r2Secrets" ] hmModules null;
          importsList = [
            inputs.sops-nix.homeManagerModules.sops
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.stateVersion;
              }
            )
          ]
          ++ baseModuleImports
          ++ [
            (if r2SecretsModule != null then r2SecretsModule else { })
            (if context7SecretsModule != null then context7SecretsModule else { })
          ]
          ++ appModulesRaw;
          appsForUsers = hmModules.apps or { };
        in
        {
          useGlobalPkgs = true;
          extraSpecialArgs = {
            hasGlobalPkgs = true;
            inherit inputs;
          };
          backupFileExtension = "hm.bk";
          users.${ownerName}.imports = importsList;
        };

    };
  };
}
