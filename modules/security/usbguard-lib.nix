{ lib, ... }:
{
  flake.lib.security.usbguard =
    let
      baseRules = ''
        # Allow USB hubs so topology can enumerate
        allow with-interface equals { 09:*:* }

        # Allow Human Interface Devices (keyboards, mice, digitizers)
        allow with-interface equals { 03:00:* }
        allow with-interface equals { 03:01:* }
        allow with-interface equals { 03:02:* }
      '';

      defaultAuditRules = [
        "-w /var/lib/usbguard/rules.conf -p wa -k usbguard-policy"
        "-w /var/lib/usbguard/IPCAccessControl.d -p wa -k usbguard-ipc"
        "-w /etc/usbguard -p wa -k usbguard-config"
        "-w /run/current-system/sw/bin/usbguard -p x -k usbguard-cli"
        "-w /run/current-system/sw/bin/usbguard-daemon -p x -k usbguard-daemon"
      ];

    in
    {
      inherit baseRules defaultAuditRules;

      mkRules =
        extraRules:
        let
          extraList =
            if extraRules == null then
              [ ]
            else
              (
                assert lib.isList extraRules || throw "usbguard.mkRules expects a list of rule strings";
                extraRules
              );
          ruleset = [
            (lib.strings.trim baseRules)
          ]
          ++ lib.filter (rule: rule != "") (map lib.strings.trim extraList);
        in
        lib.concatStringsSep "\n\n" ruleset;
    };
}
