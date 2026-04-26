{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
{
  configurations.nixos.tpnix.module = config.flake.lib.nixos.r2.mkHostR2Module {
    inherit
      inputs
      metaOwner
      secretsRoot
      ;
    policy = {
      enableExternalFlake = false;
      sopsRuntimeReady = false;
      disabledReason = "tpnix R2 runtime services are disabled until SOPS decryption keys are configured.";
    };
  };
}
