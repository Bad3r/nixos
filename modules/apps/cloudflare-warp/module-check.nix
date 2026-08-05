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
          warpModule =
            let
              found = findModule "cloudflare-warp" config.flake.nixosModules.apps;
            in
            assert lib.assertMsg (
              found != null
            ) "apps/cloudflare-warp-module-eval: cloudflare-warp app export is missing";
            found;
          mkNixos =
            {
              secretsRoot,
              enable ? true,
            }:
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.sops-nix.nixosModules.sops
                warpModule
                {
                  nixpkgs.config.allowUnfree = true;
                  networking.firewall.checkReversePath = "loose";
                  programs.cloudflare-warp.extended = {
                    inherit enable;
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
          disabled = mkNixos {
            secretsRoot = "${./cloudflare-warp-check-fixtures}/missing";
            enable = false;
          };
          enrolledAttrs =
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp/organization" enrolled.config.sops.secrets)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare organization secret";
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp-mdm" enrolled.config.sops.templates)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare mdm template";
            assert lib.assertMsg (
              !lib.hasInfix "UN-ENROLLED" enrolled.config.systemd.services.cloudflare-warp-connect.script
            ) "apps/cloudflare-warp-module-eval: enrolled connect script must not carry the un-enrolled guard";
            assert lib.assertMsg
              (lib.hasInfix "warp-cli --accept-tos registration organization" enrolled.config.systemd.services.cloudflare-warp-connect.script)
              "apps/cloudflare-warp-module-eval: enrolled connect script must verify managed registration";
            assert
              let
                connectScript = enrolled.config.systemd.services.cloudflare-warp-connect.script;
                parts = lib.splitString "warp-cli --accept-tos connect" connectScript;
                beforeConnect = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "if [ -n \"$managed_org\" ] && [ -n \"$managed_registration\" ]; then" beforeConnect
                )
                "apps/cloudflare-warp-module-eval: enrolled connect script must gate connect on managed enrollment";
            {
              execStartPre = enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre;
              templateContent = enrolled.config.sops.templates."cloudflare-warp-mdm".content;
              connectScript = enrolled.config.systemd.services.cloudflare-warp-connect.script;
              restartTriggers = enrolled.config.systemd.services.cloudflare-warp.restartTriggers;
            };
          unenrolledAttrs =
            assert lib.assertMsg (
              !builtins.hasAttr "cloudflare-warp/organization" unenrolled.config.sops.secrets
            ) "apps/cloudflare-warp-module-eval: un-enrolled branch must not declare organization secret";
            assert
              let
                connectScript = unenrolled.config.systemd.services.cloudflare-warp-connect.script;
                parts = lib.splitString "warp-cli --accept-tos connect" connectScript;
                beforeConnect = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "<4>cloudflare-warp-connect: device is UN-ENROLLED" beforeConnect
                  && lib.hasInfix "exit 0" beforeConnect
                )
                "apps/cloudflare-warp-module-eval: un-enrolled connect script must warn and exit before warp-cli connect";
            {
              connectScript = unenrolled.config.systemd.services.cloudflare-warp-connect.script;
              execStartPre = unenrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre;
              restartTriggers = unenrolled.config.systemd.services.cloudflare-warp.restartTriggers;
              warnings = unenrolled.config.warnings;
            };
          disabledAttrs =
            assert lib.assertMsg (
              !disabled.config.services.cloudflare-warp.enable
            ) "apps/cloudflare-warp-module-eval: disabled branch must not enable upstream WARP";
            assert lib.assertMsg
              (builtins.elem "r /var/lib/cloudflare-warp/mdm.xml" disabled.config.systemd.tmpfiles.rules)
              "apps/cloudflare-warp-module-eval: disabled branch must remove managed mdm.xml";
            {
              tmpfilesRules = disabled.config.systemd.tmpfiles.rules;
            };
        in
        builtins.deepSeq
          {
            inherit enrolledAttrs unenrolledAttrs disabledAttrs;
          }
          (
            pkgs.runCommandLocal "cloudflare-warp-module-eval-ok" { } ''
              echo "ok: both Cloudflare WARP enrollment branches evaluated" > $out
            ''
          );
    };
}
