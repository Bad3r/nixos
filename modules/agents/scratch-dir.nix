# The TMPDIR agents utilize instead of /tmp.
{
  config,
  lib,
  metaOwner,
  ...
}:
let
  mountGateFor =
    config.flake.lib.nixos._localMirrorsMountGate
      or (throw "modules/git/mirror-root.nix no longer exports flake.lib.nixos._localMirrorsMountGate");
  inherit (config.flake.lib.agents) scratchDir;
in
{
  options.flake.lib.agents.scratchDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "/data/agents";
    description = "Agent scratch root: the wrappers' TMPDIR and the scratch-guard redirect target.";
  };

  config.flake.nixosModules.hosts-common =
    {
      config,
      pkgs,
      utils,
      ...
    }:
    {
      # A mount-gated oneshot, not tmpfiles: /data is nofail, so tmpfiles would
      # create the directory on the root filesystem when the volume is absent.
      systemd.services.agents-scratch-dir = {
        description = "Provision the agent scratch directory";
        wantedBy = [ "multi-user.target" ];
        inherit (mountGateFor scratchDir config.fileSystems utils) after unitConfig;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = utils.escapeSystemdExecArgs [
            "${pkgs.coreutils}/bin/install"
            "-d"
            "-m"
            "0700"
            "-o"
            metaOwner.username
            "-g"
            "users"
            scratchDir
          ];
        };
      };
    };
}
