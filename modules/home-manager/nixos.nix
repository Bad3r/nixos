{
  config,
  inputs,
  lib,
  ...
}:

let
  inherit (lib)
    attrByPath
    mkDefault
    mkIf
    mkMerge
    mkOption
    types
    ;

  moduleArgs = config._module.args or { };
  inputsArg = moduleArgs.inputs or { };
  flakeAttrs = config.flake or { };

  hmModulesFromConfig = attrByPath [ "homeManagerModules" ] { } flakeAttrs;
  hmModulesFromArgs = moduleArgs.homeManagerModules or { };
  hmModulesFromInputsArg = attrByPath [ "self" "outputs" "homeManagerModules" ] { } inputsArg;
  hmModulesFromInputs = attrByPath [ "self" "outputs" "homeManagerModules" ] { } inputs;

  hmModules =
    if hmModulesFromConfig != { } then
      hmModulesFromConfig
    else if hmModulesFromArgs != { } then
      hmModulesFromArgs
    else if hmModulesFromInputsArg != { } then
      hmModulesFromInputsArg
    else
      hmModulesFromInputs;

  hmApps = hmModules.apps or { };
  hasApp = name: lib.hasAttr name hmApps;
  getApp =
    name:
    if hasApp name then
      lib.getAttr name hmApps
    else
      throw "Home Manager base module: unknown app '${name}' referenced by base imports";

  preferredOwner = moduleArgs.homeManagerOwner or (inputs.homeManagerOwner or null);

  ownerUsername =
    let
      ownerMeta = attrByPath [ "lib" "meta" "owner" "username" ] null config.flake;
      fallbackOwnerName =
        let
          usersAttrs = config.users.users or { };
          normalUsers = lib.filterAttrs (_: u: (u.isNormalUser or false)) usersAttrs;
        in
        if normalUsers != { } then lib.head (lib.attrNames normalUsers) else null;
    in
    if ownerMeta != null && ownerMeta != "" then
      ownerMeta
    else if preferredOwner != null && preferredOwner != "" then
      preferredOwner
    else if fallbackOwnerName != null then
      fallbackOwnerName
    else
      throw "Home Manager base module: unable to determine owner username (define config.flake.lib.meta.owner.username or at least one normal user).";

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

  extraAppImports = attrByPath [ "home-manager" "extraAppImports" ] [ ] config;
  allAppImports = lib.unique (defaultAppImports ++ extraAppImports);

  ctxSecretsPath = if inputs ? secrets then inputs.secrets + "/context7.yaml" else null;
  hasContext7Secrets = ctxSecretsPath != null && builtins.pathExists ctxSecretsPath;
  gatedAppImports =
    if hasContext7Secrets then
      allAppImports
    else
      lib.subtractLists [ "codex" "claude-code" ] allAppImports;

  calendarDefaults = _: {
    accounts = {
      calendar.basePath = lib.mkDefault ".local/share/calendars";
      contact.basePath = lib.mkDefault ".local/share/contacts";
    };
  };

  baseOptions = {
    home-manager.extraAppImports = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional Home Manager app keys appended to the default app list.";
    };
  };

  baseConfig = mkMerge [
    {
      _module.args.homeManagerModules = lib.mkForce hmModules;
      flake.homeManagerModules = lib.mkForce hmModules;
    }
    (mkIf (ownerUsername != null) {
      _module.args.homeManagerOwner = mkDefault ownerUsername;

      home-manager = {
        useGlobalPkgs = true;
        extraSpecialArgs = {
          hasGlobalPkgs = true;
          inherit inputs;
        };
        backupFileExtension = "hm.bk";

        users.${ownerUsername} = {
          imports =
            let
              baseModule = attrByPath [ "base" ] hmModules null;
              requiredBase =
                if baseModule != null then
                  baseModule
                else
                  throw "Home Manager base module: expected flake.homeManagerModules.base to be available.";
            in
            [
              inputs.sops-nix.homeManagerModules.sops
              (
                { osConfig, ... }:
                {
                  home.stateVersion = osConfig.system.stateVersion;
                }
              )
              requiredBase
              (attrByPath [ "r2Secrets" ] hmModules { })
              (attrByPath [ "context7Secrets" ] hmModules { })
              calendarDefaults
            ]
            ++ map getApp gatedAppImports;
        };
      };
    })
  ];

in
{
  flake.nixosModules.base = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];
    options = baseOptions;
    config = baseConfig;
  };
}
