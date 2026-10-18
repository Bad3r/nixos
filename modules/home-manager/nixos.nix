{
  config,
  inputs,
  lib,
  metaOwner,
  secretsRoot,
  ...
}:
let
  ownerName = metaOwner.username;

  moduleArgs = config._module.args or { };
  baseArgs = {
    inherit
      config
      inputs
      lib
      metaOwner
      secretsRoot
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
      formatModuleList =
        modules: lib.concatMapStringsSep "\n          - " (m: "homeManagerModules.${m}") modules;
    in
    if module != null then
      module
    else
      throw ''
        Missing Home Manager module at: ${builtins.concatStringsSep "." (map toString attrPath)}

        Available top-level modules:
          - ${formatModuleList availableModules}

        Searched in:
          - config.flake.homeManagerModules.${builtins.concatStringsSep "." (map toString hmAttrPath)}
          - inputs.self.homeManagerModules.${builtins.concatStringsSep "." (map toString hmAttrPath)}
          - File: ${toString path}
      '';

  stateVersionModule =
    { osConfig, ... }:
    {
      home.stateVersion = osConfig.system.stateVersion;
      home.enableNixpkgsReleaseCheck = false;
    };
  baseModule = loadHomeModule ../home-manager/base.nix [
    "flake"
    "homeManagerModules"
    "base"
  ];
  sopsRuntimeModule = loadHomeModule ../home-manager/sops-runtime.nix [
    "flake"
    "homeManagerModules"
    "sopsRuntime"
  ];
  context7Module = loadHomeModule ../home/context7-secrets.nix [
    "flake"
    "homeManagerModules"
    "context7Secrets"
  ];
  geckoSecretsModule = loadHomeModule ../home/gecko-secrets.nix [
    "flake"
    "homeManagerModules"
    "geckoSecrets"
  ];
  r2Module = loadHomeModule ../home/r2-secrets.nix [
    "flake"
    "homeManagerModules"
    "r2Secrets"
  ];
  virustotalModule = loadHomeModule ../home/virustotal-secrets.nix [
    "flake"
    "homeManagerModules"
    "virustotalSecrets"
  ];

  coreModules = [
    stateVersionModule
    baseModule
    sopsRuntimeModule
    context7Module
    geckoSecretsModule
    r2Module
    virustotalModule
  ];

in
{
  flake.nixosModules = {
    base = {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      config.home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {
          hasGlobalPkgs = true;
          inherit
            inputs
            metaOwner
            secretsRoot
            ;
          inherit (config.flake.lib) agents;
        };
        backupFileExtension = "hm.bk";

        users.${ownerName} = {
          # Explicitly set these - don't rely on home-manager auto-detection
          home.username = ownerName;
          home.homeDirectory = "/home/${ownerName}";

          imports = coreModules;
        };
      };
    };
  };
}
