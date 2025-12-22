{
  config,
  inputs,
  lib,
  ...
}:
let
  # Direct import bypasses flake-parts argument passing evaluation order issues
  metaOwner = import ../../lib/meta-owner-profile.nix;
  ownerName = metaOwner.username;

  moduleArgs = config._module.args or { };
  baseArgs = {
    inherit
      config
      inputs
      lib
      metaOwner
      ;
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

      # Helper for better error messages
      availableModules = builtins.attrNames hmModules;
      availableApps = if builtins.hasAttr "apps" hmModules then builtins.attrNames hmModules.apps else [ ];
    in
    if module != null then
      module
    else
      throw ''
        Missing Home Manager module at: ${builtins.concatStringsSep "." (map toString attrPath)}

        Available top-level modules: ${builtins.toString availableModules}
        Available app modules: ${builtins.toString availableApps}

        Searched in:
          - config.flake.homeManagerModules
          - inputs.self.homeManagerModules
          - File: ${toString path}
      '';

  loadAppModule =
    name:
    let
      filePath = ../hm-apps + "/${name}.nix";
      moduleFromConfig = lib.attrByPath [ "apps" name ] null hmModules;
      availableApps = if builtins.hasAttr "apps" hmModules then builtins.attrNames hmModules.apps else [ ];
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
      throw ''
        Home Manager app module not found: ${name}

        Expected file: ${toString filePath}
        Available apps: ${builtins.toString availableApps}

        Hint: Check that the file exists or the module is exported in homeManagerModules.apps
      '';

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
          inherit inputs metaOwner;
        };
        backupFileExtension = "hm.bk";

        users.${ownerName} = {
          # Explicitly set these - don't rely on home-manager auto-detection
          home.username = ownerName;
          home.homeDirectory = "/home/${ownerName}";

          imports = coreModules ++ appModules;
        };
      };
    };
  };
}
