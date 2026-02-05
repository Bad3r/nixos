{
  lib,
  pkgs,
  inputs,
  metaOwner,
  ...
}:
let
  usbguardLib =
    let
      libAttrs = import ../security/usbguard-lib.nix { inherit lib; };
      flakeLib = libAttrs.flake or { };
      securityLib = (flakeLib.lib or { }).security or { };
    in
    securityLib.usbguard or { };
  baseRules = lib.strings.trim (usbguardLib.baseRules or "");
  baseRulesFile = pkgs.writeText "usbguard-base.rules" baseRules;
  defaultsModule = usbguardLib.defaultsModule or null;
  moduleImports = lib.optional (defaultsModule != null) defaultsModule;
  ownerUsername = metaOwner.username;

  hostSlug = "system76";
  secretDir = inputs.secrets + "/usbguard";
  secretFile = secretDir + "/${hostSlug}.yaml";
  secretName = "usbguard/${hostSlug}.rules";
  secretRuntimePath = "/run/secrets/usbguard/${hostSlug}.rules";
  secretExists = builtins.pathExists secretFile;

  runtimeRuleFile = "/var/lib/usbguard/rules.conf";

  # Set to false to disable USBGuard entirely
  enabled = false;
in
{
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      imports = moduleImports;

      config = lib.mkMerge [
        {
          services.usbguard.enable = lib.mkForce enabled;
        }
        (lib.mkIf enabled {
          services.usbguard = {
            rules = lib.mkForce null;
            ruleFile = lib.mkForce runtimeRuleFile;
            IPCAllowedUsers = lib.mkForce (
              lib.unique [
                "root"
                ownerUsername
              ]
            );
            IPCAllowedGroups = lib.mkForce [ "wheel" ];
            dbus.enable = lib.mkForce true;
          };

          systemd.services.usbguard = {
            after = lib.mkAfter [ "sops-install-secrets.service" ];
            preStart = lib.mkAfter ''
              install -D -m 0600 /dev/null ${runtimeRuleFile}
              cat ${baseRulesFile} > ${runtimeRuleFile}
              if [ -s "${secretRuntimePath}" ] && [ -r "${secretRuntimePath}" ]; then
                printf '\n# Host-specific overrides loaded from ${secretRuntimePath}\n' >> ${runtimeRuleFile}
                cat "${secretRuntimePath}" >> ${runtimeRuleFile}
              fi
            '';
            serviceConfig = {
              LogExtraFields = lib.mkForce [
                "POLICY=usbguard"
                "SUBSYSTEM=usb"
              ];
              # Allow reading secrets during preStart
              ReadWritePaths = lib.mkAfter [ "/run/secrets/usbguard" ];
            };
          };

          # Audit subsystem disabled due to incomplete LSM stacking support
          #
          # ROOT CAUSE: Kernel 6.18.2 lacks full multi-LSM audit support
          #
          # This system uses LSM stacking: lsm=landlock,yama,bpf,apparmor
          # The kernel audit subsystem's security_lsmprop_to_secctx() function
          # fails when multiple LSMs are active, causing:
          #   - audit: error in audit_log_subj_ctx (repeated hundreds of times)
          #   - audit_panic: callbacks suppressed
          #   - All auditctl operations fail with status 255
          #
          # TESTED: Enabling security.auditd does NOT fix this - errors persist
          #
          # This is a known kernel limitation being actively addressed in mainline:
          # Kernel patches v2-v6 (Dec 2024 - Aug 2025) add "multiple task security
          # contexts" support to the audit subsystem for LSM stacking scenarios.
          #
          # SOLUTION: Disable audit until kernel with full LSM stacking audit support
          # is available. USBGuard enforcement still works, only audit logging is lost.
          #
          # References:
          # - Linux kernel audit mailing list: "Audit: Add record for multiple task
          #   security contexts" patch series
          # - security_lsmprop_to_secctx fails with LSM=landlock,yama,bpf,apparmor
          security.audit.enable = lib.mkForce false;
          security.auditd.enable = lib.mkForce false;
        })
        (lib.mkIf (enabled && secretExists) {
          sops.secrets.${secretName} = {
            sopsFile = secretFile;
            path = secretRuntimePath;
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "usbguard.service" ];
          };
        })
        (lib.mkIf enabled {
          systemd.tmpfiles.rules = [
            "f /var/lib/usbguard/rules.conf 0600 root root -"
            "d /var/lib/usbguard/IPCAccessControl.d 0700 root root -"
          ];
        })
      ];
    };
}
