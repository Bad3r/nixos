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

  loadHomeModule =
    path: attrPath:
    let
      exported = import path;
      evaluated = if lib.isFunction exported then exported baseArgs else exported;
      module = lib.attrByPath attrPath null evaluated;
    in
    if module != null then
      module
    else
      throw ("Missing Home Manager module at " + builtins.concatStringsSep "." (map toString attrPath));

  loadAppModule =
    name:
    let
      filePath = ../hm-apps + "/${name}.nix";
    in
    if builtins.pathExists filePath then
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
  stylixModules = loadHomeModule ../style/stylix.nix [
    "flake"
    "homeManagerModules"
  ];
  stylixBaseModule = lib.attrByPath [ "base" ] null stylixModules;
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
  stylixExtras = lib.filter (m: m != null) [ stylixBaseModule ];
  coreModules = [
    sopsModule
    stateVersionModule
    baseModule
    context7Module
    r2Module
  ]
  ++ stylixExtras;

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
