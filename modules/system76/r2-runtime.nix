{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
{
  configurations.nixos.system76.module = config.flake.lib.nixos.r2.mkHostR2Module {
    inherit
      inputs
      metaOwner
      secretsRoot
      ;
    policy = {
      enableExternalFlake = true;
      sopsRuntimeReady = true;
      disabledReason = "system76 R2 runtime is disabled; requires policy.enableExternalFlake, policy.sopsRuntimeReady, and secrets/r2.yaml.";
    };
  };
}
