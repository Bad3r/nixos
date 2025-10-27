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
          usersAttrs = config.users.users or { };
          normalUsers = lib.filterAttrs (_: u: (u.isNormalUser or false)) usersAttrs;
          warnlessRenameModule =
            { lib, ... }:
            let
              patchedLib = lib.extend (
                _final: prev: {
                  mkRenamedOptionModule =
                    from: to:
                    prev.doRename {
                      inherit from to;
                      visible = false;
                      warn = false;
                      use = prev.id;
                    };
                  mkRenamedOptionModuleWith =
                    args:
                    prev.doRename {
                      inherit (args) from to;
                      visible = false;
                      warn = false;
                      use = prev.id;
                    };
                }
              );
            in
            {
              _module.args.lib = patchedLib;
            };
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
            combined;
          configBase = lib.attrByPath [ "base" ] hmModules null;
          flattenImportTree =
            value:
            let
              nestedImports = importsValue: if importsValue == null then [ ] else flattenImportTree importsValue;
              contentImports = attrs: lib.attrByPath [ "imports" ] [ ] (lib.attrByPath [ "content" ] { } attrs);
              shouldDescendImports =
                attrs:
                attrs ? imports
                && !(attrs ? config)
                && !(attrs ? options)
                && !(attrs ? config')
                && !(attrs ? _type && attrs._type == "override");
            in
            if value == null then
              [ ]
            else if lib.isList value then
              lib.concatMap flattenImportTree value
            else if lib.isAttrs value then
              if value ? _type && value._type == "import-tree" then
                nestedImports (contentImports value)
              else if value ? _type && value._type == "order" then
                nestedImports (contentImports value)
              else if value ? _type && value ? content then
                flattenImportTree value.content
              else if shouldDescendImports value then
                nestedImports value.imports
              else
                [ value ]
            else
              [ value ];
          moduleRawKey =
            module:
            if lib.isAttrs module && module ? _file then
              module._file
            else if lib.isAttrs module && module ? imports then
              let
                imports = module.imports or [ ];
              in
              if imports == [ ] then
                null
              else
                let
                  candidate = lib.head imports;
                in
                if lib.isAttrs candidate && candidate ? _file then
                  candidate._file
                else if builtins.isPath candidate then
                  toString candidate
                else if builtins.isString candidate then
                  candidate
                else
                  null
            else
              null;
          baseModulePayload =
            if lib.isAttrs configBase && lib.hasAttr "base" configBase then configBase.base else configBase;
          baseModuleImportsRaw =
            if lib.isAttrs baseModulePayload then lib.attrByPath [ "imports" ] [ ] baseModulePayload else [ ];
          baseModulesRaw =
            let
              flattened = flattenImportTree baseModuleImportsRaw;
              filtered =
                let
                  result = lib.filter (
                    module:
                    let
                      rawKey = moduleRawKey module;
                    in
                    !(
                      rawKey != null
                      && (
                        lib.hasInfix ", via option flake.homeManagerModules.apps." rawKey
                        || lib.hasInfix ", via option flake.homeManagerModules.gui" rawKey
                        || lib.hasInfix ", via option flake.homeManagerModules.context7Secrets" rawKey
                        || lib.hasInfix ", via option flake.homeManagerModules.r2Secrets" rawKey
                      )
                    )
                  ) flattened;
                in
                result;
            in
            if filtered == [ ] then
              throw "Home Manager base module: expected flake.homeManagerModules.base to be available."
            else
              filtered;
          moduleFromBase =
            key:
            if lib.isAttrs configBase && lib.hasAttr key configBase then
              lib.getAttr key configBase
            else
              lib.attrByPath [ key ] hmModules null;
          hmApps =
            let
              rawValue = moduleFromBase "apps";
              result = if rawValue == null then { } else rawValue;
            in
            result;
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
            "starship"
            "wezterm"
          ];
          extraAppImports = lib.attrByPath [ "home-manager" "extraAppImports" ] [ ] config;
          allAppImports = defaultAppImports ++ extraAppImports;
          appModules =
            let
              modules = lib.concatMap flattenImportTree (map getApp allAppImports);
            in
            modules;
          guiModule = moduleFromBase "gui";
          guiModules = flattenImportTree guiModule;
          context7SecretsModules = flattenImportTree (moduleFromBase "context7Secrets");
          r2SecretsModules = flattenImportTree (moduleFromBase "r2Secrets");
          baseModules = baseModulesRaw;
          baseImports = [
            inputs.sops-nix.homeManagerModules.sops
            (
              { osConfig, ... }:
              {
                home.stateVersion = osConfig.system.stateVersion;
              }
            )
          ];
          bundleImports = lib.concatLists [
            baseModules
            guiModules
            appModules
            context7SecretsModules
            r2SecretsModules
          ];
        in
        {
          useGlobalPkgs = true;
          extraSpecialArgs = {
            hasGlobalPkgs = true;
            inherit inputs;
          };
          backupFileExtension = "hm.bk";
          sharedModules = lib.mkBefore [ warnlessRenameModule ];
          users.${ownerName}.imports = baseImports ++ bundleImports;
        };

    };
  };
}
