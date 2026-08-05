/*
  Check: force both SOPS branches of the Cloudflare WARP app module.

  CI intentionally has no secrets submodule, so normal host evaluation only
  takes the un-enrolled branch. Use an in-repo non-secret fixture to force the
  managed branch and deep-force the template, secret-backed ExecStartPre, and
  connect script. A missing fixture path keeps the un-enrolled assertions in
  the same check.
*/
{
  lib,
  inputs,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."apps/cloudflare-warp-module-eval" =
        let
          findModule =
            name: module:
            if builtins.isList module then
              let
                findIn =
                  modules:
                  if modules == [ ] then
                    null
                  else
                    let
                      candidate = findModule name (builtins.head modules);
                    in
                    if candidate != null then candidate else findIn (builtins.tail modules);
              in
              findIn module
            else if builtins.isAttrs module then
              if builtins.hasAttr name module then module.${name} else findModule name (module.imports or [ ])
            else
              null;
          warpModule = findModule "cloudflare-warp" config.flake.nixosModules.apps;
          mkNixos =
            { secretsRoot }:
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.sops-nix.nixosModules.sops
                warpModule
                {
                  nixpkgs.config.allowUnfree = true;
                  networking.firewall.checkReversePath = "loose";
                  programs.cloudflare-warp.extended = {
                    enable = true;
                    serviceMode = "warp";
                    autoConnect = 0;
                    switchLocked = false;
                    connectOnBoot = true;
                  };
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                  system.stateVersion = "26.05";
                }
              ];
              specialArgs = { inherit secretsRoot; };
            };
          enrolled = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
          };
          unenrolled = mkNixos {
            secretsRoot = "${./cloudflare-warp-check-fixtures}/missing";
          };
          enrolledAttrs =
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp/organization" enrolled.config.sops.secrets)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare organization secret";
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp-mdm" enrolled.config.sops.templates)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare mdm template";
            {
              execStartPre = enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre;
              templateContent = enrolled.config.sops.templates."cloudflare-warp-mdm".content;
              connectScript = enrolled.config.systemd.services.cloudflare-warp-connect.script;
            };
          unenrolledAttrs =
            assert lib.assertMsg (
              !builtins.hasAttr "cloudflare-warp/organization" unenrolled.config.sops.secrets
            ) "apps/cloudflare-warp-module-eval: un-enrolled branch must not declare organization secret";
            {
              connectScript = unenrolled.config.systemd.services.cloudflare-warp-connect.script;
              warnings = unenrolled.config.warnings;
            };
        in
        builtins.deepSeq
          {
            inherit enrolledAttrs unenrolledAttrs;
          }
          (
            pkgs.runCommandLocal "cloudflare-warp-module-eval-ok" { } ''
              echo "ok: both Cloudflare WARP enrollment branches evaluated" > $out
            ''
          );
    };
}
