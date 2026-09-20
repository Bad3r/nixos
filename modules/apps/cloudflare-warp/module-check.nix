/*
  Check: force the enrolled branch of the Cloudflare WARP app module.

  CI has no secrets submodule, so every host closure takes the un-enrolled
  branch and nothing evaluates the sops declarations or the mdm.xml template.
  A fixture secrets root holding a non-secret cloudflare-warp.yaml, together
  with hostName = "tpnix" (a registry host whose sopsRuntimeReady is true),
  forces the enrolled branch here. A missing fixture root and a host outside
  the registry cover two of the three warning paths in the same check; the
  third, a registered host with sopsRuntimeReady = false, needs a registry
  entry the flake does not carry. A second enrolled system with
  sops.useSystemdActivation covers the unit ordering the fleet's
  activation-script hosts never exercise. The two enrolled systems run the two
  modes, so the rendered service_mode and the resolved routing that only
  `warp` adds are asserted both ways.
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
          # The module argument, not config.flake.lib.nixos: the helper read
          # back through the flake.lib option merge is a wrapper whose
          # functionArgs are empty, so the module system could not inject pkgs.
          warpModule = nixosAppHelpers.getApp "cloudflare-warp";
          # Built once and shared by all four fixtures below: leaving
          # nixpkgs.pkgs unset makes each nixosSystem call import and evaluate
          # its own nixpkgs tree from nixpkgs.config.allowUnfree alone.
          pkgsUnfree = import inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          mkNixos =
            {
              secretsRoot,
              serviceMode ? "warp",
              hostName ? "tpnix",
              extraModules ? [ ],
            }:
            inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.sops-nix.nixosModules.sops
                warpModule
                {
                  # nixpkgs.nix asserts nixpkgs.config == {} whenever
                  # nixpkgs.pkgs is set, so allowUnfree has to travel with the
                  # shared instance instead of as a sibling module option.
                  nixpkgs.pkgs = pkgsUnfree;
                  programs.cloudflare-warp.extended = {
                    enable = true;
                    inherit serviceMode;
                  };
                  # Module output only, never decryption: the fixture is not
                  # a sops file.
                  sops.validateSopsFiles = false;
                  sops.age.keyFile = "/dev/null";
                  # The warp route is gated on resolved, so every system runs it
                  # and only mode and enrollment decide the route.
                  services.resolved.enable = true;
                  system.stateVersion = "26.05";
                }
              ]
              ++ extraModules;
              specialArgs = {
                inherit hostName secretsRoot;
              };
            };
          enrolled = mkNixos {
            secretsRoot = ./module-check-fixtures;
            serviceMode = "tunnelonly";
          };
          systemdActivation = mkNixos {
            secretsRoot = ./module-check-fixtures;
            extraModules = [ { sops.useSystemdActivation = true; } ];
          };
          unenrolled = mkNixos { secretsRoot = "${./module-check-fixtures}/missing"; };
          unregistered = mkNixos {
            secretsRoot = ./module-check-fixtures;
            hostName = "unregistered";
          };
          template = enrolled.config.sops.templates."cloudflare-warp-mdm";
          hostsTemplate = enrolled.config.sops.templates."cloudflare-warp-hosts";
          warpUnitOf = system: system.config.systemd.services.cloudflare-warp;
          sopsUnit = "sops-install-secrets.service";
          secretOf = name: enrolled.config.sops.secrets."cloudflare-warp/${name}";
          placeholderOf = name: enrolled.config.sops.placeholder."cloudflare-warp/${name}";
          # Whitespace-free so a key and its value can be matched as one
          # string: a swap between two <string> bodies survives every
          # single-element match.
          packedOf =
            system:
            lib.replaceStrings [ "\n" " " ] [ "" "" ]
              system.config.sops.templates."cloudflare-warp-mdm".content;
          packed = packedOf enrolled;
          pairs = name: lib.hasInfix "<key>${name}</key><string>${placeholderOf name}</string>" packed;
          modeOf =
            system: mode: lib.hasInfix "<key>service_mode</key><string>${mode}</string>" (packedOf system);
          check = name: cond: lib.assertMsg cond "apps/cloudflare-warp-module-eval: ${name}";
          resolveOf = system: { inherit (system.config.services.resolved.settings.Resolve) DNS Domains; };
          dnsUnitOf = system: system.config.systemd.services.cloudflare-warp-dns or null;
          tunnelDevice = "sys-subsystem-net-devices-CloudflareWARP.device";
          dropIn = "/run/systemd/resolved.conf.d/cloudflare-warp.conf";
          # `main` fails on a stopped resolved, which would fail a clean teardown.
          reloadsResolved = [
            "--kill-whom=all"
            "--signal=SIGHUP systemd-resolved.service"
          ];
          route = lib.findFirst (
            trigger: trigger ? text && lib.hasInfix "DNS=127.0.2.2 127.0.2.3" trigger.text
          ) null (warpUnitOf systemdActivation).restartTriggers;
          # A command holding every `first` fragment runs before one holding every `next` fragment.
          runsBefore =
            commands: first: next:
            let
              indexOf =
                fragments: lib.lists.findFirstIndex (cmd: lib.all (f: lib.hasInfix f cmd) fragments) null commands;
            in
            indexOf first != null && indexOf next != null && indexOf first < indexOf next;
          linkResolve = {
            DNS = [ ];
            Domains = [ ];
          };
        in
        assert check "organization pairs with its placeholder" (pairs "organization");
        assert check "auth_client_id pairs with its placeholder" (pairs "auth_client_id");
        assert check "auth_client_secret pairs with its placeholder" (pairs "auth_client_secret");
        assert check "service_mode follows the option in both modes" (
          modeOf enrolled "tunnelonly" && modeOf systemdActivation "warp"
        );
        assert check "auto_connect is 0" (
          lib.hasInfix "<key>auto_connect</key><integer>0</integer>" packed
        );
        assert check "template stays on the sops tmpfs" (
          template.path == "/run/secrets/rendered/cloudflare-warp-mdm"
        );
        assert check "unit bind-mounts the render into the WARP state directory" (
          lib.elem "${template.path}:/var/lib/cloudflare-warp/mdm.xml" (warpUnitOf enrolled)
          .serviceConfig.BindReadOnlyPaths
        );
        # systemd.services.<name> creates a unit as readily as it extends one,
        # and restartUnits takes any string: without this anchor an upstream
        # rename would leave the bind mount and the restart hook on a stub
        # while the real daemon starts without mdm.xml, and everything green.
        assert check
          "cloudflare-warp.service is the upstream warp-svc daemon, not a stub this module created"
          (lib.hasSuffix "/bin/warp-svc" ((warpUnitOf enrolled).serviceConfig.ExecStart or ""));
        assert check "template is root-only" (template.mode == "0600");
        assert check "template restarts warp-svc" (template.restartUnits == [ "cloudflare-warp.service" ]);
        # Requires= on a unit that does not exist fails the dependent's start,
        # which is why the helper gates the dependency on useSystemdActivation.
        assert check "activation-script hosts do not depend on the absent sops-install-secrets unit" (
          !(lib.elem sopsUnit (warpUnitOf enrolled).requires)
          && !(lib.elem sopsUnit (warpUnitOf enrolled).after)
        );
        assert check "systemd-activation hosts start warp-svc after sops-install-secrets" (
          lib.elem sopsUnit (warpUnitOf systemdActivation).after
          && lib.elem sopsUnit (warpUnitOf systemdActivation).requires
        );
        assert check "organization key" ((secretOf "organization").key == "organization");
        assert check "auth_client_id key is per host" (
          (secretOf "auth_client_id").key == "tpnix/auth_client_id"
        );
        assert check "auth_client_secret key is per host" (
          (secretOf "auth_client_secret").key == "tpnix/auth_client_secret"
        );
        assert check "Mesh CIDR is read from SOPS" ((secretOf "mesh-cidr").key == "mesh/cidr");
        assert check "tpnix Mesh address is read from SOPS" (
          (secretOf "mesh-host-tpnix").key == "mesh/hosts/tpnix"
        );
        assert check "songbird Mesh address is read from SOPS" (
          (secretOf "mesh-host-songbird").key == "mesh/hosts/songbird"
        );
        assert check "enrolled host runs the service" enrolled.config.services.cloudflare-warp.enable;
        assert check "enrolled host keeps the upstream UDP opening off" (
          !enrolled.config.services.cloudflare-warp.openFirewall
        );
        assert check "Mesh host mappings use only SOPS placeholders" (
          lib.hasInfix "${placeholderOf "mesh-host-tpnix"} tpnix.internal" hostsTemplate.content
          && lib.hasInfix "${placeholderOf "mesh-host-songbird"} songbird.internal" hostsTemplate.content
        );
        assert check "Mesh host mappings preserve the standard localhost entry" (
          lib.hasInfix "127.0.0.1 localhost" hostsTemplate.content
        );
        assert check "the deployed hosts file comes from the SOPS template" (
          enrolled.config.environment.etc.hosts.source == hostsTemplate.path
          && hostsTemplate.path == "/run/secrets/rendered/cloudflare-warp-hosts"
        );
        assert check "the deployed hosts file is readable and refreshes NSS caching" (
          hostsTemplate.mode == "0444" && hostsTemplate.restartUnits == [ "nscd.service" ]
        );
        assert check "unenrolled host renders no Mesh hosts template" (
          !(unenrolled.config.sops.templates ? "cloudflare-warp-hosts")
        );
        assert check "unenrolled host preserves NixOS's store-backed hosts file" (
          lib.hasPrefix "/nix/store/" (toString unenrolled.config.environment.etc.hosts.source)
          && !(unenrolled.config.sops.secrets ? "cloudflare-warp/mesh-cidr")
          && !(unenrolled.config.sops.secrets ? "cloudflare-warp/mesh-host-tpnix")
        );
        # A static global route would outlive the tunnel and leave no resolver
        # while warp-svc is down.
        assert check "warp mode keeps resolved's static settings on the link servers" (
          resolveOf systemdActivation == linkResolve
        );
        assert check "tunnel churn cannot trip the unit's start limit" (
          lib.hasInfix "\nStartLimitIntervalSec=0\n"
            systemdActivation.config.systemd.units."cloudflare-warp-dns.service".text
        );
        # Type=oneshot with no RemainAfterExit goes inactive the moment
        # ExecStart returns, and ExecStopPost then deletes the drop-in it just
        # installed; the render must also stay readable by resolved, which
        # parses it as systemd-resolve rather than root.
        assert check "the route outlives ExecStart and stays readable by resolved" (
          (dnsUnitOf systemdActivation).serviceConfig.RemainAfterExit
          && lib.any (lib.hasInfix "install -D -m 0644 ") (dnsUnitOf systemdActivation)
          .serviceConfig.ExecStart
        );
        assert check "warp mode binds the proxy route to the tunnel device" (
          let
            unit = dnsUnitOf systemdActivation;
          in
          unit != null && lib.elem tunnelDevice unit.bindsTo && lib.elem tunnelDevice unit.wantedBy
        );
        assert check "the route sends every name to the client's DNS proxy" (
          lib.any (
            trigger:
            trigger ? text
            && lib.hasInfix "DNS=127.0.2.2 127.0.2.3" trigger.text
            && lib.hasInfix "Domains=~." trigger.text
          ) (warpUnitOf systemdActivation).restartTriggers
        );
        # bindsTo and the route text alone stay green with the install or the
        # SIGHUP dropped, which leaves resolved on the link servers.
        assert check "starting the unit installs the route where resolved reads it, then reloads resolved" (
          route != null
          && runsBefore (dnsUnitOf systemdActivation).serviceConfig.ExecStart [
            (builtins.unsafeDiscardStringContext "${route}")
            " ${dropIn}"
          ] reloadsResolved
        );
        # A failed start runs ExecStopPost, and the tunnel that is already up
        # never starts the unit again.
        assert check "a failed reload at start leaves the route installed" (
          lib.any (
            cmd: lib.hasPrefix "-" cmd && lib.all (fragment: lib.hasInfix fragment cmd) reloadsResolved
          ) (dnsUnitOf systemdActivation).serviceConfig.ExecStart
        );
        assert check "stopping the unit removes the route, then reloads resolved" (
          runsBefore (dnsUnitOf systemdActivation).serviceConfig.ExecStopPost [
            "rm -f ${dropIn}"
          ] reloadsResolved
        );
        assert check "tunnelonly adds no proxy route" (dnsUnitOf enrolled == null);
        assert check "an unenrolled host never points resolved at the absent proxy" (
          dnsUnitOf unenrolled == null
        );
        assert check "enrolled host does not warn" (
          !lib.any (lib.hasInfix "Cloudflare WARP enrollment is disabled on") enrolled.config.warnings
        );
        assert check "missing secret leaves the service off" (
          !unenrolled.config.services.cloudflare-warp.enable
        );
        assert check "missing secret warns" (
          lib.any (lib.hasInfix "secrets/cloudflare-warp.yaml is missing") unenrolled.config.warnings
        );
        assert check "host outside the registry leaves the service off" (
          !unregistered.config.services.cloudflare-warp.enable
        );
        assert check "host outside the registry warns about the missing entry" (
          lib.any (lib.hasInfix "has no flake.lib.nixos.hosts entry") unregistered.config.warnings
        );
        assert check "host outside the registry renders no template" (
          !(unregistered.config.sops.templates ? "cloudflare-warp-mdm")
          && !(unregistered.config.sops.templates ? "cloudflare-warp-hosts")
        );
        pkgs.runCommandLocal "cloudflare-warp-module-eval-ok" { } "touch $out";
    };
}
