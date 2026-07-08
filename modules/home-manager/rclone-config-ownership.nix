/*
  Check: rclone.conf ownership boundary (issue #121).

  modules/hm-apps/rclone.nix owns ~/.config/rclone/rclone.conf whenever
  programs.rclone.extended.enable is set. The r2-flake Home Manager module can
  render the same path through programs.r2-cloud.enableRcloneRemote (upstream
  default: true). These checks evaluate synthetic Home Manager configurations
  to prove that:

  - the safe split keeps the repo activation writer as the only owner,
  - the colliding combination fails evaluation,
  - a relocated programs.r2-cloud.rcloneConfigPath is accepted,
  - a populated programs.rclone.remotes fails evaluation (this one is
    independent of the r2-flake input, so it runs even when that input is
    unavailable).

  Each scenario differs from a passing baseline only in the
  enableRcloneRemote/rcloneConfigPath/remotes values, so a failing scenario
  is attributable to the ownership assertions without matching on message
  text. Home Manager gates config access behind its own failed-assertion
  throw, which is why the failing scenarios are probed with tryEval instead
  of reading config.assertions.
*/
{
  config,
  inputs,
  lib,
  secretsRoot,
  ...
}:
let
  r2HomeModuleAvailable = lib.hasAttrByPath [
    "r2-flake"
    "homeManagerModules"
    "default"
  ] inputs;
  r2HomeModule = lib.getAttrFromPath [
    "r2-flake"
    "homeManagerModules"
    "default"
  ] inputs;
in
{
  perSystem =
    { pkgs, ... }:
    let
      mkRcloneHome =
        scenarioModules:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              home = {
                username = "hm-smoke";
                homeDirectory = "/tmp/hm-smoke";
                stateVersion = (lib.importJSON "${inputs.home-manager}/release.json").release;
                enableNixpkgsReleaseCheck = false;
              };
              programs.home-manager.enable = true;
            }
            inputs.sops-nix.homeManagerModules.sops
            config.flake.homeManagerModules.apps.rclone
          ]
          ++ scenarioModules;
          extraSpecialArgs = {
            inherit secretsRoot;
            # Mirrors the host shape from modules/apps/rclone.nix: extended
            # rclone enabled with the gdrive env secret declared system-side.
            osConfig = {
              programs.rclone.extended.enable = true;
              sops.secrets."rclone/gdrive-env".path = "/run/secrets/rclone/gdrive-env";
            };
          };
        };

      # Mirrors the host wiring in modules/lib/r2-runtime.nix.
      safeSplit = mkRcloneHome (
        lib.optionals r2HomeModuleAvailable [
          r2HomeModule
          {
            programs.r2-cloud = {
              enable = true;
              accountId = "smoke-account-id";
              enableRcloneRemote = false;
            };
          }
        ]
      );

      # Leaves enableRcloneRemote at its upstream default (true), the exact
      # drift the ownership assertion must reject.
      collidingRemote = mkRcloneHome [
        r2HomeModule
        {
          programs.r2-cloud = {
            enable = true;
            accountId = "smoke-account-id";
          };
        }
      ];

      relocatedRemote = mkRcloneHome [
        r2HomeModule
        (
          { config, ... }:
          {
            programs.r2-cloud = {
              enable = true;
              accountId = "smoke-account-id";
              enableRcloneRemote = true;
              rcloneConfigPath = "${config.xdg.configHome}/rclone/r2-cloud.conf";
            };
          }
        )
      ];

      # Uses the upstream option shape (remotes.<name>.config, with the
      # required "type" key) so the scenario is valid for the Home Manager
      # rclone module and the only eval failure it can hit is the
      # remotes-ownership assertion in modules/hm-apps/rclone.nix.
      remotesConflict = mkRcloneHome [
        {
          programs.rclone.remotes.smoke.config = {
            type = "s3";
            provider = "Cloudflare";
          };
        }
      ];

      collidingEval = builtins.tryEval collidingRemote.config.home.username;

      remotesConflictEval = builtins.tryEval remotesConflict.config.home.username;
    in
    {
      checks."home-manager/rclone-config-ownership" =
        assert lib.assertMsg (
          safeSplit.config.home.activation ? configureRcloneConfig
        ) "rclone.conf safe split lost the modules/hm-apps/rclone.nix activation writer";
        assert lib.assertMsg (
          !(safeSplit.config.xdg.configFile ? "rclone/rclone.conf")
        ) "rclone.conf safe split unexpectedly manages rclone.conf through xdg.configFile";
        assert lib.assertMsg (
          (!r2HomeModuleAvailable) || !collidingEval.success
        ) "programs.r2-cloud.enableRcloneRemote colliding with the repo-owned rclone.conf was not rejected";
        assert lib.assertMsg (
          (!r2HomeModuleAvailable) || relocatedRemote.config.xdg.configFile ? "rclone/r2-cloud.conf"
        ) "relocated programs.r2-cloud.rcloneConfigPath did not render rclone/r2-cloud.conf";
        assert lib.assertMsg (
          (!r2HomeModuleAvailable) || relocatedRemote.config.home.activation ? configureRcloneConfig
        ) "relocated programs.r2-cloud.rcloneConfigPath lost the repo activation writer";
        assert lib.assertMsg (
          !remotesConflictEval.success
        ) "non-empty programs.rclone.remotes colliding with the repo-owned rclone.conf was not rejected";
        pkgs.runCommand "rclone-config-ownership" { } "echo ok > $out";
    };
}
