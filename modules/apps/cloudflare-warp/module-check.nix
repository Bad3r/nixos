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
  nixosAppHelpers,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      checks."apps/cloudflare-warp-module-eval" =
        let
          # Use the module argument, not config.flake.lib.nixos: the same helper
          # read back through the flake.lib option merge returns a merged wrapper
          # whose functionArgs are empty, so the module system cannot inject pkgs.
          warpModule = nixosAppHelpers.getApp "cloudflare-warp";
          mkNixos =
            {
              secretsRoot,
              enable ? true,
              extraSettings ? { },
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
                  }
                  // extraSettings;
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                  system.stateVersion = "26.05";
                }
              ];
              specialArgs = { inherit secretsRoot; };
            };
          # Non-default port and firewall choice: both option defaults match
          # upstream's, so only diverging values prove the wrapper forwards them.
          enrolled = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraSettings = {
              udpPort = 24080;
              openFirewall = false;
            };
          };
          unenrolled = mkNixos {
            secretsRoot = "${./cloudflare-warp-check-fixtures}/missing";
          };
          disabled = mkNixos {
            secretsRoot = "${./cloudflare-warp-check-fixtures}/missing";
            enable = false;
          };
          hasWarpCli =
            system:
            lib.any (
              drv: (lib.getName drv) == "cloudflare-warp-headless"
            ) system.config.environment.systemPackages;
          enrolledConnect = enrolled.config.systemd.services.cloudflare-warp-connect;
          enrolledConnectScript = enrolledConnect.script;
          enrolledWarp = enrolled.config.services.cloudflare-warp;
          enrolledAttrs =
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp/organization" enrolled.config.sops.secrets)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare organization secret";
            assert lib.assertMsg (builtins.hasAttr "cloudflare-warp-mdm" enrolled.config.sops.templates)
              "apps/cloudflare-warp-module-eval: enrolled branch must declare mdm template";
            assert lib.assertMsg enrolledWarp.enable
              "apps/cloudflare-warp-module-eval: enrolled branch must enable upstream WARP";
            assert lib.assertMsg (
              lib.getName enrolledWarp.package == "cloudflare-warp-headless"
            ) "apps/cloudflare-warp-module-eval: enrolled branch must forward the headless package";
            assert lib.assertMsg (
              enrolledWarp.udpPort == 24080
              && !enrolledWarp.openFirewall
              && !(builtins.elem 24080 enrolled.config.networking.firewall.allowedUDPPorts)
            ) "apps/cloudflare-warp-module-eval: enrolled branch must forward udpPort and openFirewall";
            # sops compares the rendered template between generations, so it
            # already covers every mdm field. A second restart owner on the unit
            # restarts warp-svc twice for one activation.
            assert lib.assertMsg (
              enrolled.config.sops.templates."cloudflare-warp-mdm".restartUnits == [ "cloudflare-warp.service" ]
              && enrolled.config.systemd.services.cloudflare-warp.restartTriggers == [ ]
            ) "apps/cloudflare-warp-module-eval: the mdm template must be the only restart owner of warp-svc";
            assert lib.assertMsg
              (lib.hasInfix "xmllint --noout" (
                lib.head enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre
              ))
              "apps/cloudflare-warp-module-eval: enrolled branch must parse the rendered mdm.xml before installing it";
            # Restart=always respawns warp-svc without an explicit restart job,
            # which PartOf does not propagate; Upholds re-runs the oneshot.
            assert lib.assertMsg
              (
                enrolledConnect.bindsTo == [ "cloudflare-warp.service" ]
                && enrolledConnect.partOf == [ ]
                && enrolled.config.systemd.services.cloudflare-warp.upholds == [ "cloudflare-warp-connect.service" ]
              )
              "apps/cloudflare-warp-module-eval: connect oneshot must re-run after an unexpected warp-svc restart";
            assert lib.assertMsg enrolledConnect.enableStrictShellChecks
              "apps/cloudflare-warp-module-eval: connect script must be shellcheck-gated";
            assert lib.assertMsg
              (lib.hasInfix "warp-cli --accept-tos registration organization" enrolledConnectScript)
              "apps/cloudflare-warp-module-eval: enrolled connect script must verify managed registration";
            # The capture is compared for exact equality, so 2>&1 would report an
            # enrolled device as unmanaged, and 2>/dev/null would drop warp-cli's
            # own reason for a failed check from the journal.
            assert lib.assertMsg
              (lib.hasInfix ''registration="$(timeout 5s warp-cli --accept-tos registration organization)"'' enrolledConnectScript)
              "apps/cloudflare-warp-module-eval: the registration capture must leave stderr unredirected";
            assert lib.assertMsg
              (lib.hasInfix "managed organization secret unavailable; cannot verify registration" enrolledConnectScript)
              "apps/cloudflare-warp-module-eval: enrolled connect script must reject an empty managed organization";
            assert
              let
                parts = lib.splitString "warp-cli --accept-tos connect" enrolledConnectScript;
                beforeConnect = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "if [ \"$registration_state\" = \"confirmed\" ]; then" beforeConnect
                )
                "apps/cloudflare-warp-module-eval: enrolled connect script must gate connect on a confirmed registration";
            # An unanswered registration check must not be treated as an
            # unmanaged tunnel, so the disconnect belongs to the mismatch branch
            # alone. The length guard keeps a renamed marker from degrading this
            # into a whole-script search that always passes.
            assert
              let
                parts = lib.splitString "warp-cli disconnect" enrolledConnectScript;
                beforeDisconnect = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "mismatch)" beforeDisconnect
                  && !lib.hasInfix "could not be verified" beforeDisconnect
                )
                "apps/cloudflare-warp-module-eval: enrolled connect script must disconnect only on a confirmed registration mismatch";
            # One definition plus one call site at the top of each attempt.
            # warp-cli connect does not change the registration organization, so
            # a second check per attempt only spends IPC budget.
            assert lib.assertMsg
              (lib.length (lib.splitString "refresh_registration" enrolledConnectScript) == 3)
              "apps/cloudflare-warp-module-eval: enrolled connect script must refresh the registration once per attempt";
            assert
              let
                parts = lib.splitString "while [ -z \"$connected\" ]" enrolledConnectScript;
                beforeLoop = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "managed organization secret unavailable; not connecting" beforeLoop
                  && lib.hasInfix "exit 0" beforeLoop
                )
                "apps/cloudflare-warp-module-eval: enrolled connect script must exit before the retry loop when the managed organization is empty";
            # A live tunnel whose registration never answered is terminal: the
            # loop has nothing left to request and must not spend its full budget.
            assert lib.assertMsg
              (
                lib.hasInfix "unverified=$((unverified + 1))" enrolledConnectScript
                && lib.hasInfix "[ \"$unverified\" -lt 3 ]" enrolledConnectScript
              )
              "apps/cloudflare-warp-module-eval: enrolled connect script must stop retrying once the tunnel is up and unverifiable";
            {
              execStartPre = enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre;
              templateContent = enrolled.config.sops.templates."cloudflare-warp-mdm".content;
              connectScript = enrolledConnectScript;
            };
          unenrolledAttrs =
            assert lib.assertMsg (
              !builtins.hasAttr "cloudflare-warp/organization" unenrolled.config.sops.secrets
            ) "apps/cloudflare-warp-module-eval: un-enrolled branch must not declare organization secret";
            # warp-svc holds CAP_NET_ADMIN and an open UDP port, and without
            # mdm.xml it serves only consumer WARP, so it must stay down.
            assert lib.assertMsg (
              !unenrolled.config.services.cloudflare-warp.enable
            ) "apps/cloudflare-warp-module-eval: un-enrolled branch must not start warp-svc";
            assert lib.assertMsg (
              !builtins.hasAttr "cloudflare-warp-connect" unenrolled.config.systemd.services
            ) "apps/cloudflare-warp-module-eval: un-enrolled branch must not declare the connect oneshot";
            assert lib.assertMsg (hasWarpCli unenrolled)
              "apps/cloudflare-warp-module-eval: un-enrolled branch must still install warp-cli";
            assert lib.assertMsg
              (builtins.elem "r /var/lib/cloudflare-warp/mdm.xml" unenrolled.config.systemd.tmpfiles.rules)
              "apps/cloudflare-warp-module-eval: un-enrolled branch must remove a stale managed mdm.xml";
            {
              tmpfilesRules = unenrolled.config.systemd.tmpfiles.rules;
              warnings = unenrolled.config.warnings;
            };
          disabledAttrs =
            assert lib.assertMsg (
              !disabled.config.services.cloudflare-warp.enable
            ) "apps/cloudflare-warp-module-eval: disabled branch must not enable upstream WARP";
            assert lib.assertMsg (
              !(hasWarpCli disabled)
            ) "apps/cloudflare-warp-module-eval: disabled branch must not install warp-cli";
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
