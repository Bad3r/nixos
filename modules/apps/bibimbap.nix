/*
  Package: bibimbap
  Description: Launcher that opens Pulsar's Bibimbap web driver in a Chrome app window with a profile of its own.
  Homepage: https://bbb.pulsar.gg/
  Documentation: https://support.pulsar.gg/hc/en-us/articles/58653339537177-How-can-I-use-the-web-driver-Bibimbap
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Bibimbap configures Pulsar mice over WebHID, which only Chromium-based browsers implement.
    * The session user gets the Feinmann F01 Noctua Edition's configuration interface, no other HID interface, plus the firmware bootloaders.

  Notes:
    * The profile lives in $XDG_DATA_HOME/bibimbap.
    * A managed Chrome policy grants the site the cable and dongle IDs, so launches reconnect without the HID chooser.
*/
_:
let
  vendorId = "3710";
  productIds = [
    # Feinmann F01 Noctua Edition over its USB-C cable.
    "7507"
    # LINK 2 dongle.
    "5504"
  ];
  # On both IDs, interface 1 is the vendor-defined (usage page 0xFF05)
  # configuration channel. Interface 0 carries pointer input and interface 2
  # the macro keystrokes, so neither is granted.
  configInterface = "01";
  # Firmware updates restart the device under one of these IDs, which carry
  # only the update channel. The dongle's D1 bootloader is f005; f004 sits
  # beside it in Bibimbap's device list and is presumed to be the mouse's.
  bootloaderIds = [
    "f004"
    "f005"
  ];

  bibimbapPackage =
    {
      lib,
      writeShellApplication,
      makeDesktopItem,
      symlinkJoin,
      chrome,
    }:
    let
      launcher = writeShellApplication {
        name = "bibimbap";
        text = ''
          # The mouse page reopens the last device without the HID chooser.
          exec ${lib.getExe chrome} \
            --app=https://bbb.pulsar.gg/cMouse/ \
            --user-data-dir="''${XDG_DATA_HOME:-$HOME/.local/share}/bibimbap" \
            --no-first-run \
            --no-default-browser-check \
            --hide-scrollbars \
            "$@"
        '';
      };

      desktopItem = makeDesktopItem {
        name = "bibimbap";
        desktopName = "Bibimbap";
        genericName = "Pulsar device configuration";
        comment = "Configure Pulsar mice through the Bibimbap web driver";
        exec = "bibimbap";
        icon = "input-mouse";
        terminal = false;
        keywords = [
          "Pulsar"
          "Noctua"
          "Feinmann"
          "mouse"
          "fan"
        ];
        categories = [
          "Settings"
          "HardwareSettings"
        ];
      };
    in
    symlinkJoin {
      name = "bibimbap";
      paths = [
        launcher
        desktopItem
      ];
    };

  BibimbapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bibimbap.extended;

      # Sort window is 61..72: 60-persistent-hidraw.rules sets the ID_USB_*
      # properties matched below, and 73-seat-late.rules acts on uaccess.
      udevRules = pkgs.writeTextFile {
        name = "bibimbap-udev-rules";
        destination = "/etc/udev/rules.d/70-bibimbap.rules";
        text =
          lib.concatMapStrings (productId: ''
            KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ENV{ID_USB_VENDOR_ID}=="${vendorId}", ENV{ID_USB_MODEL_ID}=="${productId}", ENV{ID_USB_INTERFACE_NUM}=="${configInterface}", TAG+="uaccess"
          '') productIds
          + lib.concatMapStrings (productId: ''
            KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ENV{ID_USB_VENDOR_ID}=="${vendorId}", ENV{ID_USB_MODEL_ID}=="${productId}", TAG+="uaccess"
          '') bootloaderIds;
      };
    in
    {
      options.programs.bibimbap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bibimbap.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.callPackage bibimbapPackage {
            chrome = config.programs.google-chrome.extended.package;
          };
          defaultText = lib.literalExpression "generated bibimbap launcher package";
          description = "The bibimbap package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.google-chrome.extended.enable = lib.mkOverride 1050 true;

        environment.systemPackages = [ cfg.package ];
        services.udev.packages = [ udevRules ];

        # Chrome keeps a chooser grant across reconnects only for devices with
        # a USB serial, and the dongle reports none since firmware 5.08.
        programs.google-chrome.extended.webHidAllowDevicesForUrls = [
          {
            devices = map (productId: { inherit vendorId productId; }) productIds;
            urls = [ "https://bbb.pulsar.gg" ];
          }
        ];
      };
    };
in
{
  flake.nixosModules.apps.bibimbap = BibimbapModule;
}
