/*
  Package: winapps
  Description: Home Manager configuration for the WinApps launcher and the Outlook Classic menu entry.
  Homepage: https://github.com/winapps-org/winapps
  Documentation: https://github.com/winapps-org/winapps/blob/main/README.md
  Repository: https://github.com/winapps-org/winapps

  Summary:
    * Writes ~/.config/winapps/winapps.conf from the guest module's name, address and account, with the password read through packages/winapps-askpass.
    * Installs an Outlook Classic desktop entry that runs `winapps manual` on the Outlook executable, and creates the one host directory the session shares.

  Notes:
    * Gated on programs.winapps.extended.enable from the NixOS scope and loaded per host through extraHomeApps.
    * No RDP_PASS, +home-drive, /drives or /cert: flag: the launcher inherits nothing beyond the values written here.
    * The guest path of OUTLOOK.EXE is checked in docs/winapps/remoteapp-setup.md.
*/
_: {
  flake.homeManagerModules.apps.winapps =
    {
      osConfig,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [
        "programs"
        "winapps"
        "extended"
        "enable"
      ] false osConfig;
      inherit (osConfig.programs.winapps.extended) package;
      guest = osConfig.host.virtualization.windowsGuest;
      askpass = pkgs.callPackage ../../packages/winapps-askpass { };
      transferDir = "${config.home.homeDirectory}/Documents/Outlook-Transfer";
      wmClass = "outlook-classic";
      # Click-to-Run layout of Office; docs/winapps/remoteapp-setup.md compares it with the guest.
      outlookExe = "C:\\Program Files\\Microsoft Office\\root\\Office16\\OUTLOOK.EXE";
      # A quoted Exec= argument writes every backslash four times; the script keeps the path out of the desktop file.
      launchOutlook = pkgs.writeShellScript "outlook-classic" ''
        exec ${package}/bin/winapps manual ${lib.escapeShellArg outlookExe}
      '';
    in
    {
      config = lib.mkIf nixosEnabled {
        # bin/winapps expands the flag variables unquoted, so no value may hold whitespace.
        # No /cert: flag: bin/winapps starts xfreerdp as a background job with stdin on /dev/null,
        # so the trust prompt for an unknown certificate reads EOF and refuses it.
        # REMOVABLE_MEDIA silences a per-launch notice; only `winapps <app> <file>` shares it.
        # -grab-keyboard keeps the full desktop from swallowing the i3 bindings.
        xdg.configFile."winapps/winapps.conf".text = ''
          WAFLAVOR="libvirt"
          VM_NAME="${guest.name}"
          RDP_IP="${guest.network.guestAddress}"
          RDP_USER="${guest.rdpUser}"
          RDP_ASKPASS="${lib.getExe askpass}"
          RDP_SCALE="100"
          AUTOPAUSE="off"
          RDP_FLAGS="/sound /drive:transfer,${transferDir}"
          RDP_FLAGS_NON_WINDOWS="/wm-class:${wmClass}"
          RDP_FLAGS_WINDOWS="-grab-keyboard"
          REMOVABLE_MEDIA="${transferDir}"
        '';

        home.activation.ensureOutlookTransferDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p '${transferDir}'
          chmod 700 '${transferDir}'
        '';

        xdg.desktopEntries.outlook-classic = {
          name = "Outlook Classic";
          genericName = "Mail Client";
          exec = "${launchOutlook}";
          icon = "${package}/src/apps/outlook/icon.svg";
          categories = [
            "Office"
            "Email"
          ];
          # xfreerdp never completes the startup-notification sequence, so a busy
          # cursor would otherwise run through the whole guest boot.
          startupNotify = false;
          settings.StartupWMClass = wmClass;
        };
      };
    };
}
