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

      config.home-manager =
        let
          flakeAttrs = config.flake or { };
          ownerMeta = lib.attrByPath [ "lib" "meta" "owner" ] { } flakeAttrs;
          moduleArgs = config._module.args or { };
          inputsArg = moduleArgs.inputs or { };
          hmModulesFromConfig = lib.attrByPath [ "homeManagerModules" ] { } flakeAttrs;
          hmModulesFromArgs = moduleArgs.homeManagerModules or { };
          hmModulesFromInputs = lib.attrByPath [ "self" "homeManagerModules" ] { } inputsArg;
          hmModules =
            let
              candidates = [ hmModulesFromConfig hmModulesFromArgs hmModulesFromInputs ];
              pick = lib.findFirst (candidate: candidate != { }) { } candidates;
            in
            if pick != { } then pick else throw "Home Manager base module: unable to locate flake.homeManagerModules bundle.";
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
          combinedAppImports = lib.unique (defaultAppImports ++ extraAppImports);
          ctxSecretsPath = if inputs ? secrets then inputs.secrets + "/context7.yaml" else null;
          hasContext7Secrets = ctxSecretsPath != null && builtins.pathExists ctxSecretsPath;
          gatedAppImports =
            if hasContext7Secrets then
              combinedAppImports
            else
              lib.subtractLists [ "codex" "claude-code" ] combinedAppImports;
          hmKeys = lib.concatStringsSep "," (builtins.attrNames hmModules);
          baseModule = hmModules.base or null;
          requiredBase =
            builtins.trace ("home-manager.nixos: hmModules keys=" + hmKeys)
              (if baseModule != null then baseModule else
                throw "Home Manager base module: expected flake.homeManagerModules.base to be available.");
          ownerUsername =
            let
              fallbackOwnerName =
                let
                  usersAttrs = config.users.users or { };
                  normalUsers = lib.filterAttrs (_: user: user.isNormalUser or false) usersAttrs;
                in
                if normalUsers != { } then lib.head (lib.attrNames normalUsers) else null;
              explicitOwner = ownerMeta.username or null;
            in
            if explicitOwner != null then
              explicitOwner
            else if fallbackOwnerName != null then
              fallbackOwnerName
            else
              throw "Home Manager base module: unable to determine owner username (set config.flake.lib.meta.owner.username or define a normal user).";
          sharedBaseModulesWithoutTrace = lib.unique (
            [
              inputs.sops-nix.homeManagerModules.sops
              ({ osConfig, ... }:
                {
                  home.stateVersion = osConfig.system.stateVersion;
                  accounts = {
                    calendar.basePath = lib.mkDefault ".local/share/calendars";
                    contact.basePath = lib.mkDefault ".local/share/contacts";
                  };
                }
              )
              requiredBase
            ]
            ++ lib.optional (hmModules ? r2Secrets) (lib.getAttr "r2Secrets" hmModules)
            ++ lib.optional (hmModules ? context7Secrets) (lib.getAttr "context7Secrets" hmModules)
          );
          describeModule =
            module:
            if builtins.isAttrs module && module ? _file then
              toString module._file
            else if builtins.isAttrs module && module ? imports then
              "attrs:imports"
            else if builtins.isFunction module then
              "function"
            else
              builtins.typeOf module;
          sharedBaseModules =
            let
              desc = builtins.map describeModule sharedBaseModulesWithoutTrace;
            in
            builtins.trace
              (
                "home-manager.nixos: sharedBaseModules length="
                + builtins.toString (builtins.length sharedBaseModulesWithoutTrace)
                + " descriptions="
                + builtins.toString desc
              )
              sharedBaseModulesWithoutTrace;
          appImports =
            let result = map getApp gatedAppImports; in
            builtins.trace (
              "home-manager.nixos: appImports length="
              + builtins.toString (builtins.length result)
            ) result;
        in
        {
          useGlobalPkgs = true;
          extraSpecialArgs = {
            hasGlobalPkgs = true;
            inherit inputs;
          };
          backupFileExtension = "hm.bk";

          sharedModules = lib.mkDefault sharedBaseModules;
          users.${ownerUsername}.imports = appImports;
        };
    };
  };
}
