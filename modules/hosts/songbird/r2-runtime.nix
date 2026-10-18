{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
let
  ready = config.flake.lib.nixos.hosts.songbird.r2RuntimeReady;
in
{
  configurations.nixos.songbird.module = config.flake.lib.nixos.r2.mkHostR2Module {
    inherit
      inputs
      metaOwner
      secretsRoot
      ;
    policy = {
      enableExternalFlake = ready;
      sopsRuntimeReady = ready;
      disabledReason = "songbird R2 runtime is disabled; set flake.lib.nixos.hosts.songbird.r2RuntimeReady = true and provide secrets/r2.yaml.";
    };
  };
}
