{
  config,
  inputs,
  metaOwner,
  secretsRoot,
  ...
}:
let
  ready = config.flake.lib.nixos.hosts.tpnix.sopsRuntimeReady;
in
{
  configurations.nixos.tpnix.module = config.flake.lib.nixos.r2.mkHostR2Module {
    inherit
      inputs
      metaOwner
      secretsRoot
      ;
    policy = {
      enableExternalFlake = ready;
      sopsRuntimeReady = ready;
      disabledReason = "tpnix R2 runtime services are disabled until SOPS decryption keys are configured.";
    };
  };
}
