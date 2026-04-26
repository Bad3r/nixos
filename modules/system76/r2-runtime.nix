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
      enableExternalFlake = false;
      sopsRuntimeReady = false;
      disabledReason = "system76 R2 integration is disabled until the upstream r2-flake stops referencing removed pkgs.nodePackages.";
    };
  };
}
