{
  config,
  inputs,
  lib,
  ...
}:
let
  ownerName =
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
    );

  moduleArgs = config._module.args or { };
  baseArgs = {
    inherit config inputs lib;
  }
  // moduleArgs;

  flakeAttrs = config.flake or { };
  moduleInputs = moduleArgs.inputs or { };
  hmModulesFromConfig = lib.attrByPath [ "homeManagerModules" ] { } flakeAttrs;
  hmModulesFromModuleInputs = lib.attrByPath [ "self" "homeManagerModules" ] { } moduleInputs;
  hmModulesFromSelf = lib.attrByPath [ "homeManagerModules" ] { } (inputs.self or { });
  hmModules = lib.foldl' (acc: src: acc // src) { } [
    hmModulesFromSelf
    hmModulesFromModuleInputs
    hmModulesFromConfig
  ];

  stripHomeManagerPrefix =
    attrPath:
    if
      (builtins.length attrPath) >= 2
      && (builtins.head attrPath) == "flake"
      && (builtins.elemAt attrPath 1) == "homeManagerModules"
    then
      lib.drop 2 attrPath
    else
      attrPath;

  loadHomeModule =
    path: attrPath:
    let
      hmAttrPath = stripHomeManagerPrefix attrPath;
      moduleFromConfig = if hmAttrPath == [ ] then null else lib.attrByPath hmAttrPath null hmModules;
      fallbackModule =
        let
          exported = import path;
          evaluated = if lib.isFunction exported then exported baseArgs else exported;
        in
        lib.attrByPath attrPath null evaluated;
      module = if moduleFromConfig != null then moduleFromConfig else fallbackModule;
    in
    if module != null then
      module
    else
      throw ("Missing Home Manager module at " + builtins.concatStringsSep "." (map toString attrPath));

  loadAppModule =
    name:
    let
      filePath = ../hm-apps + "/${name}.nix";
      moduleFromConfig = lib.attrByPath [ "apps" name ] null hmModules;
    in
    if moduleFromConfig != null then
      moduleFromConfig
    else if builtins.pathExists filePath then
      loadHomeModule filePath [
        "flake"
        "homeManagerModules"
        "apps"
        name
      ]
    else
      throw ("Home Manager app module file not found: " + toString filePath);

  sopsModule = inputs.sops-nix.homeManagerModules.sops;
  stateVersionModule =
    { osConfig, ... }:
    {
      home.stateVersion = osConfig.system.stateVersion;
    };
  baseModule = loadHomeModule ../home-manager/base.nix [
    "flake"
    "homeManagerModules"
    "base"
  ];
  context7Module = loadHomeModule ../home/context7-secrets.nix [
    "flake"
    "homeManagerModules"
    "context7Secrets"
  ];
  r2Module = loadHomeModule ../home/r2-secrets.nix [
    "flake"
    "homeManagerModules"
    "r2Secrets"
  ];

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
  allAppImports = lib.unique (defaultAppImports ++ extraAppImports);
  appModules = map loadAppModule allAppImports;
  coreModules = [
    sopsModule
    stateVersionModule
    baseModule
    context7Module
    r2Module
  ];

in
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

        users.${ownerName}.imports = coreModules ++ appModules;
      };
    };
  };
}
