/*
  Check: force both SOPS branches of the Cloudflare WARP app module.

  CI intentionally has no secrets submodule, so normal host evaluation only
  takes the un-enrolled branch. Use an in-repo non-secret fixture to force the
  managed branch and deep-force the template, secret-backed ExecStartPre,
  connect script, and warnings. A missing fixture path keeps the un-enrolled
  assertions in the same check, and one fixture per managed-branch warning
  trigger proves each fires with its own text.
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
              extraConfig ? { },
            }:
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.sops-nix.nixosModules.sops
                warpModule
                {
                  nixpkgs.config.allowUnfree = true;
                  # Models a host on the hosts-common vpn-defaults baseline.
                  # mkDefault so a fixture can force the strict rp_filter the
                  # managed branch warns about.
                  networking.firewall.checkReversePath = lib.mkDefault "loose";
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
                extraConfig
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
          # Every mdm field the enrolled fixture renders sits at its option
          # default, so only diverging values prove the template forwards them.
          mdmVariant = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraSettings = {
              serviceMode = "tunnelonly";
              autoConnect = 42;
              switchLocked = true;
            };
          };
          unenrolled = mkNixos {
            secretsRoot = "${./cloudflare-warp-check-fixtures}/missing";
          };
          # enable = false with the secret present is the tpnix kill switch, and
          # the only fixture where cfg.enable is the sole thing holding the
          # managed branch shut. A missing secretsRoot here would leave every
          # assertion below passing with `managed` gated on enrolling alone.
          disabled = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            enable = false;
          };
          # Both managed-branch warnings are conditional and CI has no secrets
          # submodule, so nothing else in this repo ever reaches their
          # predicates. One fixture per trigger keeps the option paths behind
          # them (networkmanager.enable/dns, firewall.checkReversePath) honest.
          dnsConflict = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraConfig.networking.networkmanager = {
              enable = true;
              dns = "dnsmasq";
            };
          };
          # dns survives in the option even where NetworkManager never runs, so
          # this fixture pins the half of the predicate that must stay silent.
          staleDns = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraConfig.networking.networkmanager.dns = "dnsmasq";
          };
          strictRpFilter = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraConfig.networking.firewall.checkReversePath = "strict";
          };
          # connectOnBoot = false is its own mkIf branch that no other fixture
          # reaches, and the Upholds edge lives inside it.
          connectOff = mkNixos {
            secretsRoot = ./cloudflare-warp-check-fixtures;
            extraSettings.connectOnBoot = false;
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
            # The managed branch sets no environment.systemPackages of its own;
            # warp-cli reaches PATH only through upstream services.cloudflare-warp,
            # which every command in the cheatsheet and operations runbook assumes.
            assert lib.assertMsg (hasWarpCli enrolled)
              "apps/cloudflare-warp-module-eval: enrolled branch must still install warp-cli";
            # The credential fields go through config.sops.placeholder so the
            # plaintext never enters the store. Assert against that same live
            # attribute, not a hand-typed token, so swapping it for
            # sops.secrets.<x>.path or dropping a key/string pair fails here
            # instead of shipping an mdm.xml with no credentials in it.
            assert
              let
                rendered = enrolled.config.sops.templates."cloudflare-warp-mdm".content;
                placeholderOf = name: enrolled.config.sops.placeholder."cloudflare-warp/${name}";
              in
              lib.assertMsg
                (lib.all
                  (name: lib.hasInfix "<key>${name}</key>\n  <string>${placeholderOf name}</string>" rendered)
                  [
                    "organization"
                    "auth_client_id"
                    "auth_client_secret"
                  ]
                )
                "apps/cloudflare-warp-module-eval: mdm.xml must render the three credentials as sops placeholders";
            # mdm.xml is authoritative for service_mode and the module never calls
            # `warp-cli mode`, so a wrong field here is silent at runtime. Assert
            # against mdmVariant's non-default values: the enrolled fixture's are
            # all option defaults, so it would pass even against hardcoded output.
            assert
              let
                rendered = mdmVariant.config.sops.templates."cloudflare-warp-mdm".content;
              in
              lib.assertMsg
                (
                  lib.hasInfix "<key>service_mode</key>\n  <string>tunnelonly</string>" rendered
                  && lib.hasInfix "<key>auto_connect</key>\n  <integer>42</integer>" rendered
                  && lib.hasInfix "<key>switch_locked</key>\n  <true/>" rendered
                )
                "apps/cloudflare-warp-module-eval: mdm.xml must render serviceMode, autoConnect, and switchLocked";
            # switchLocked renders through a Nix `if`, so pin both arms.
            assert lib.assertMsg (lib.hasInfix "<key>switch_locked</key>\n  <false/>"
              enrolled.config.sops.templates."cloudflare-warp-mdm".content
            ) "apps/cloudflare-warp-module-eval: switchLocked false must render <false/>";
            # sops compares the rendered template between generations, so it
            # already covers every mdm field. A second restart owner on the unit
            # restarts warp-svc twice for one activation.
            assert lib.assertMsg (
              enrolled.config.sops.templates."cloudflare-warp-mdm".restartUnits == [ "cloudflare-warp.service" ]
              && enrolled.config.systemd.services.cloudflare-warp.restartTriggers == [ ]
            ) "apps/cloudflare-warp-module-eval: the mdm template must be the only restart owner of warp-svc";
            # xmllint echoes the offending source line, which is the credential,
            # so the guard has to stay fail-closed without reaching the journal:
            # suppressing stderr without `exit 1` would install a malformed
            # mdm.xml and drop warp-svc back to unmanaged mode silently.
            assert
              let
                mdmValidation = lib.head enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre;
              in
              lib.assertMsg
                (
                  lib.hasInfix "xmllint --noout" mdmValidation
                  && lib.hasInfix "2>/dev/null" mdmValidation
                  && lib.hasInfix "exit 1" mdmValidation
                )
                "apps/cloudflare-warp-module-eval: enrolled branch must parse the rendered mdm.xml before installing it, without leaking xmllint's stderr";
            # Only the xmllint guard above is pinned, so the step that actually
            # writes mdm.xml into rootDir could be deleted with the check green,
            # leaving warp-svc up on consumer WARP. lib.any over the list rather
            # than lib.last: a third entry is a harmless change that should not
            # break this, and xmllint is already pinned at lib.head.
            assert lib.assertMsg
              (lib.any (
                step:
                lib.hasInfix "/bin/install" step
                && lib.hasInfix "-m0600" step
                && lib.hasInfix "-o root" step
                && lib.hasInfix "-g root" step
                && lib.hasInfix "/var/lib/cloudflare-warp/mdm.xml" step
              ) enrolled.config.systemd.services.cloudflare-warp.serviceConfig.ExecStartPre)
              "apps/cloudflare-warp-module-eval: enrolled branch must install the rendered mdm.xml into rootDir mode 0600 root:root";
            # partOf stays empty on purpose. BindsTo already carries an explicit
            # restart through to the oneshot, and on an unexpected warp-svc exit
            # BindsTo stops the oneshot before any restart-dependency
            # propagation can reach it, so PartOf would add nothing that Upholds
            # is not already doing.
            assert lib.assertMsg
              (
                enrolledConnect.bindsTo == [ "cloudflare-warp.service" ]
                && enrolledConnect.partOf == [ ]
                && enrolled.config.systemd.services.cloudflare-warp.upholds == [ "cloudflare-warp-connect.service" ]
              )
              "apps/cloudflare-warp-module-eval: connect oneshot must re-run after an unexpected warp-svc restart";
            # nixpkgs only warns when after carries network-online.target without
            # a matching wants, and abort-on-warn is off, so pin both halves.
            assert lib.assertMsg (
              builtins.elem "network-online.target" enrolledConnect.after
              && builtins.elem "network-online.target" enrolledConnect.wants
            ) "apps/cloudflare-warp-module-eval: the connect oneshot must wait for network-online.target";
            assert lib.assertMsg enrolledConnect.enableStrictShellChecks
              "apps/cloudflare-warp-module-eval: connect script must be shellcheck-gated";
            # The exit-0-everywhere design holds only while the unit outlives the
            # retry window and warp-cli is on its PATH. DefaultTimeoutStartSec is
            # 90s, under the script's 120s deadline, so dropping the explicit
            # value SIGTERMs a run that reaches that deadline into `failed`, which
            # Upholds then restarts in a loop. Dropping cfg.package turns every
            # call into exit 127 while the unit still reports active (exited).
            assert lib.assertMsg
              (
                # `or`: a deleted setting must reach the message below rather
                # than aborting with a bare "attribute missing".
                (enrolledConnect.serviceConfig.TimeoutStartSec or null) == 180
                && (enrolledConnect.serviceConfig.RemainAfterExit or false)
                && lib.hasInfix "deadline=$((SECONDS + 120))" enrolledConnectScript
                && lib.any (entry: lib.hasInfix "cloudflare-warp" (toString entry)) enrolledConnect.path
              )
              "apps/cloudflare-warp-module-eval: the connect oneshot must outlive its retry deadline and carry warp-cli on PATH";
            assert lib.assertMsg
              (lib.hasInfix "warp-cli --accept-tos registration organization" enrolledConnectScript)
              "apps/cloudflare-warp-module-eval: enrolled connect script must verify managed registration";
            # --accept-tos is a global warp-cli option, not a per-subcommand one,
            # so every call carries it. Leaving it off disconnect in particular
            # would make the fail-closed teardown the one call that can be
            # refused, downgrading enforcement to a log line.
            # Match whole call sites, not the flag or the subcommand alone: a
            # substring search hits prose too, and a comment naming a call would
            # then fail an assertion whose message explains none of that. These
            # also pin each call's timeout and redirect shape. The registration
            # capture in particular is compared for exact equality, so 2>&1 would
            # report an enrolled device as unmanaged, while 2>/dev/null would drop
            # warp-cli's own reason for a failed check from the journal.
            assert lib.assertMsg
              (lib.all (call: lib.hasInfix call enrolledConnectScript) [
                ''registration="$(timeout -k 1s 5s warp-cli --accept-tos registration organization)"''
                ''status="$(timeout -k 1s 5s warp-cli --accept-tos status 2>&1)"''
                ''disconnect_output="$(timeout -k 1s 5s warp-cli --accept-tos disconnect 2>&1)"''
                ''request_output="$(timeout -k 1s 5s warp-cli --accept-tos connect 2>&1)"''
              ])
              "apps/cloudflare-warp-module-eval: every warp-cli call must pass --accept-tos with its bounded timeout and redirect";
            assert lib.assertMsg
              (lib.hasInfix "managed organization secret unavailable; cannot verify registration" enrolledConnectScript)
              "apps/cloudflare-warp-module-eval: enrolled connect script must reject an empty managed organization";
            # A healthy boot passes through the per-attempt states on its way to
            # confirmed, so logging them at <3> would make `journalctl -p err`
            # report every good boot as broken. Reserve <3> for states the run
            # cannot recover from and for enforcement.
            assert lib.assertMsg
              (
                lib.all (msg: lib.hasInfix "<4>cloudflare-warp-connect: ${msg}" enrolledConnectScript) [
                  "registration check failed"
                  "managed Zero Trust registration unavailable"
                  "managed enrollment is not ready; not connecting"
                  "status command failed"
                  "connect request failed"
                  "connected while the managed registration could not be verified"
                  "tunnel is up but its registration went unverified"
                ]
                && lib.all (msg: lib.hasInfix "<3>cloudflare-warp-connect: ${msg}" enrolledConnectScript) [
                  "managed organization secret unavailable"
                  "connected without managed Zero Trust registration; disconnecting"
                  "failed to disconnect unmanaged tunnel"
                  "daemon reports no Zero Trust registration"
                  "daemon is registered outside the managed organization"
                  "tunnel is not connected after"
                  "connect never succeeded"
                ]
              )
              "apps/cloudflare-warp-module-eval: per-attempt states must log at <4> and unrecoverable or enforcement states at <3>";
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
                parts = lib.splitString "warp-cli --accept-tos disconnect" enrolledConnectScript;
                beforeDisconnect = lib.head parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "mismatch)" beforeDisconnect
                  && !lib.hasInfix "could not be verified" beforeDisconnect
                )
                "apps/cloudflare-warp-module-eval: enrolled connect script must disconnect only on a confirmed registration mismatch";
            # unverified is never reset, so testing it in the terminal report
            # would let one early unanswered check on a leftover tunnel outrank
            # a live mismatch, or claim a tunnel is up after it was torn down.
            assert
              let
                parts = lib.splitString "if [ -z \"$connected\" ]; then" enrolledConnectScript;
                terminalReport = lib.last parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "if [ \"$registration_state\" = \"mismatch\" ]; then" terminalReport
                  && !lib.hasInfix "\"$unverified\"" terminalReport
                )
                "apps/cloudflare-warp-module-eval: the terminal report must branch on the live registration and status, not the cumulative unverified counter";
            # The assertion above still passes if the two mismatch sub-cases
            # collapse back into one line, and they carry different remediation:
            # an empty answer is an enrollment that never completed.
            assert
              let
                parts = lib.splitString "if [ \"$registration_state\" = \"mismatch\" ]; then" enrolledConnectScript;
                mismatchReport = lib.last parts;
              in
              lib.assertMsg
                (
                  lib.length parts > 1
                  && lib.hasInfix "if [ -z \"$registration\" ]; then" mismatchReport
                  && lib.hasInfix "daemon reports no Zero Trust registration" mismatchReport
                  && lib.hasInfix "daemon is registered outside the managed organization" mismatchReport
                )
                "apps/cloudflare-warp-module-eval: the terminal mismatch report must separate an empty registration from a foreign tenant";
            # One call site at the top of each attempt. warp-cli connect does not
            # change the registration organization, so a second check per attempt
            # only spends IPC budget. Scoped to the loop body: a whole-script
            # count also matches the definition and any comment naming it.
            assert
              let
                loopBody = lib.head (
                  lib.splitString ''if [ -n "$connected" ]'' (
                    lib.last (lib.splitString ''while [ -z "$connected" ]'' enrolledConnectScript)
                  )
                );
              in
              lib.assertMsg (lib.length (lib.splitString "refresh_registration" loopBody) == 2)
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
            # That exit path skips the loop, so it is the only place a status
            # line can come from; without it the journal has no record of the
            # tunnel for this outcome.
            assert
              let
                guarded = lib.last (lib.splitString ''if [ -z "$managed_org" ]; then'' enrolledConnectScript);
                beforeExit = lib.head (
                  lib.splitString "managed organization secret unavailable; not connecting" guarded
                );
              in
              lib.assertMsg (lib.hasInfix "refresh_status" beforeExit) "apps/cloudflare-warp-module-eval: enrolled connect script must report status before exiting on an empty managed organization";
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
              warnings = enrolled.config.warnings;
              variantTemplateContent = mdmVariant.config.sops.templates."cloudflare-warp-mdm".content;
            };
          # Forcing the managed branch's warnings list forces both lib.optional
          # predicates, so a renamed option path there fails the check instead of
          # an operator's rebuild once the sops payload lands.
          warningsAttrs =
            assert lib.assertMsg (
              !lib.any (lib.hasInfix "takes over DNS") enrolled.config.warnings
              && !lib.any (lib.hasInfix "checkReversePath is strict") enrolled.config.warnings
            ) "apps/cloudflare-warp-module-eval: a managed host on the vpn-defaults baseline must not warn";
            assert lib.assertMsg (lib.any (lib.hasInfix "takes over DNS") dnsConflict.config.warnings)
              "apps/cloudflare-warp-module-eval: a local resolver under a DNS-owning service mode must warn";
            assert lib.assertMsg (!lib.any (lib.hasInfix "takes over DNS") staleDns.config.warnings)
              "apps/cloudflare-warp-module-eval: a stale networkmanager.dns without NetworkManager must not warn";
            assert lib.assertMsg
              (lib.any (lib.hasInfix "checkReversePath is strict") strictRpFilter.config.warnings)
              "apps/cloudflare-warp-module-eval: a strict checkReversePath must warn";
            {
              dnsConflict = dnsConflict.config.warnings;
              staleDns = staleDns.config.warnings;
              strictRpFilter = strictRpFilter.config.warnings;
            };
          connectOffAttrs =
            assert lib.assertMsg (
              !builtins.hasAttr "cloudflare-warp-connect" connectOff.config.systemd.services
            ) "apps/cloudflare-warp-module-eval: connectOnBoot = false must not declare the connect oneshot";
            # Upholds is a Wants-strength edge, so a dangling target is inert
            # rather than fatal, which is exactly why nothing else would catch
            # it being hoisted out of the connectOnBoot branch.
            assert lib.assertMsg (connectOff.config.systemd.services.cloudflare-warp.upholds == [ ])
              "apps/cloudflare-warp-module-eval: connectOnBoot = false must not uphold an undeclared connect oneshot";
            {
              upholds = connectOff.config.systemd.services.cloudflare-warp.upholds;
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
            # The build warning is the only signal that an enabled host installs
            # warp-cli with no daemon behind it, which is the state both hosts
            # are in until the sops payload lands. warp-cli on PATH otherwise
            # makes an un-enrolled host look enrolled.
            assert lib.assertMsg
              (lib.any (lib.hasInfix "secrets/cloudflare-warp.yaml is missing") unenrolled.config.warnings)
              "apps/cloudflare-warp-module-eval: un-enrolled branch must warn that warp-svc is not started";
            {
              tmpfilesRules = unenrolled.config.systemd.tmpfiles.rules;
              warnings = unenrolled.config.warnings;
            };
          disabledAttrs =
            assert lib.assertMsg (
              !disabled.config.services.cloudflare-warp.enable
            ) "apps/cloudflare-warp-module-eval: disabled branch must not enable upstream WARP";
            # The documented job of the kill switch is to stop declaring secrets
            # the host can no longer decrypt, which is not the same property as
            # keeping warp-svc down. Moving the sops block to `mkIf enrolling`
            # would leave every other assertion here green while a host that lost
            # its runtime key fails activation on the payload.
            assert lib.assertMsg
              (
                !builtins.hasAttr "cloudflare-warp/organization" disabled.config.sops.secrets
                && !builtins.hasAttr "cloudflare-warp-mdm" disabled.config.sops.templates
              )
              "apps/cloudflare-warp-module-eval: disabled branch must declare no sops secrets and no mdm template";
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
            inherit
              enrolledAttrs
              unenrolledAttrs
              disabledAttrs
              warningsAttrs
              connectOffAttrs
              ;
          }
          (
            pkgs.runCommandLocal "cloudflare-warp-module-eval-ok" { } ''
              echo "ok: both Cloudflare WARP enrollment branches evaluated" > $out
            ''
          );
    };
}
