/*
  Package: realforce-connect
  Description: Launcher that opens Topre's REALFORCE CONNECT Online configurator in a Chrome app window with a profile of its own.
  Homepage: https://realforce-connect.online/
  Documentation: https://www.realforce.co.jp/en/support/download/keyboard_win.html
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * REALFORCE CONNECT Online configures the GX1 Plus (APC, keymap, illumination, firmware) over WebHID, which only Chromium-based browsers implement.
    * The session user gets the keyboard's vendor configuration interface and no other HID interface.

  Notes:
    * The profile lives in $XDG_DATA_HOME/realforce-connect.
    * A managed Chrome policy grants the site HID usage 0xFF00:0x01, so launches reconnect without the HID chooser.
*/
_:
let
  vendorId = "0853";
  # GX1 Plus US TKL (X1P). It reports no USB serial, so Chrome keeps a
  # chooser grant only for the session.
  productId = "0323";
  # Interface 2 is the vendor-defined (usage page 0xFF00) configuration
  # channel. Interfaces 0, 1, and 3 carry key and pointer input.
  configInterface = "02";
  # The site reopens the named device on a menu URL when it already holds a
  # grant for it, and falls back to its connect page otherwise.
  startUrl = "https://realforce-connect.online/apc/REALFORCE%20X1P%20US%20TKL";

  realforceConnectPackage =
    {
      lib,
      writeShellApplication,
      makeDesktopItem,
      symlinkJoin,
      chrome,
    }:
    let
      launcher = writeShellApplication {
        name = "realforce-connect";
        text = ''
          exec ${lib.getExe chrome} \
            --app=${startUrl} \
            --user-data-dir="''${XDG_DATA_HOME:-$HOME/.local/share}/realforce-connect" \
            --no-first-run \
            --no-default-browser-check \
            --hide-scrollbars \
            "$@"
        '';
      };

      desktopItem = makeDesktopItem {
        name = "realforce-connect";
        desktopName = "REALFORCE CONNECT";
        genericName = "Keyboard configuration";
        comment = "Configure the Realforce GX1 Plus through REALFORCE CONNECT Online";
        exec = "realforce-connect";
        icon = "input-keyboard";
        terminal = false;
        keywords = [
          "Realforce"
          "GX1"
          "Topre"
          "keyboard"
          "APC"
        ];
        categories = [
          "Settings"
          "HardwareSettings"
        ];
      };
    in
    symlinkJoin {
      name = "realforce-connect";
      paths = [
        launcher
        desktopItem
      ];
    };

  RealforceConnectModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.realforce-connect.extended;

      # Sort window is 61..72: 60-persistent-hidraw.rules sets the ID_USB_*
      # properties matched below, and 73-seat-late.rules acts on uaccess.
      udevRules = pkgs.writeTextFile {
        name = "realforce-connect-udev-rules";
        destination = "/etc/udev/rules.d/70-realforce-connect.rules";
        text = ''
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ENV{ID_USB_VENDOR_ID}=="${vendorId}", ENV{ID_USB_MODEL_ID}=="${productId}", ENV{ID_USB_INTERFACE_NUM}=="${configInterface}", TAG+="uaccess"
        '';
      };
    in
    {
      options.programs.realforce-connect.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable realforce-connect.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.callPackage realforceConnectPackage {
            chrome = config.programs.google-chrome.extended.package;
          };
          defaultText = lib.literalExpression "generated realforce-connect launcher package";
          description = "The realforce-connect package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.google-chrome.extended.enable = lib.mkOverride 1050 true;

        environment.systemPackages = [ cfg.package ];
        services.udev.packages = [ udevRules ];

        # A vendor and product ID grant would also expose the input
        # interfaces, and the site reopens the first granted interface with
        # the keyboard's name, which the session user cannot open.
        programs.google-chrome.extended.webHidAllowDevicesWithHidUsagesForUrls = [
          {
            usages = [
              {
                usagePage = lib.fromHexString "ff00";
                usage = 1;
              }
            ];
            urls = [ "https://realforce-connect.online" ];
          }
        ];
      };
    };
in
{
  flake.nixosModules.apps.realforce-connect = RealforceConnectModule;
}
