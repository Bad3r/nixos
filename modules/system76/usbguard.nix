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
in
{
  configurations.nixos.system76.module =
    { lib, ... }:
    {
      imports = moduleImports;

      config = lib.mkMerge [
        {
          services.usbguard = {
            enable = lib.mkForce true;
            rules = lib.mkForce ""; # Empty string instead of null - rules come from ruleFile
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
            serviceConfig.LogExtraFields = lib.mkForce [
              "POLICY=usbguard"
              "SUBSYSTEM=usb"
            ];
          };

          security.audit = {
            enable = lib.mkForce true;
            rules = usbguardLib.defaultAuditRules;
          };

          security.auditd.enable = lib.mkForce true;

        }
        (lib.optionalAttrs secretExists {
          sops.secrets.${secretName} = {
            sopsFile = secretFile;
            path = secretRuntimePath;
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "usbguard.service" ];
          };
        })
        (lib.optionalAttrs (!secretExists) { })
        {
          systemd.tmpfiles.rules = [
            "f /var/lib/usbguard/rules.conf 0600 root root -"
            "d /var/lib/usbguard/IPCAccessControl.d 0700 root root -"
          ];
        }
      ];
    };
}
