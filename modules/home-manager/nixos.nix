{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
let
  ownerName = metaOwner.username;

  stateVersionModule =
    { osConfig, ... }:
    {
      home.stateVersion = osConfig.system.stateVersion;
      home.enableNixpkgsReleaseCheck = false;
    };

  coreModules = [
    stateVersionModule
  ]
  ++ map (name: config.flake.homeManagerModules.${name}) [
    "base"
    "sopsRuntime"
    "context7Secrets"
    "geckoSecrets"
    "r2Secrets"
    "virustotalSecrets"
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
