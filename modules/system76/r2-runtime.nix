{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
let
  ready = config.flake.lib.nixos.hosts.system76.r2RuntimeReady;
in
{
  configurations.nixos.system76.module = config.flake.lib.nixos.r2.mkHostR2Module {
    inherit
      inputs
      metaOwner
      secretsRoot
      ;
    policy = {
      enableExternalFlake = ready;
      sopsRuntimeReady = ready;
      disabledReason = "system76 R2 runtime is disabled; set flake.lib.nixos.hosts.system76.r2RuntimeReady = true and provide secrets/r2.yaml.";
    };
  };
}
