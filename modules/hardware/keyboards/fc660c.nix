_:
let
  # Vial hardcodes this serial on every Vial board, so it identifies the firmware
  # but not the device; vendor, product and interface below do that.
  vialSerial = "vial:f64c2b3c";
  vendorId = "4853";
  productId = "660c";
  # Interface 1 is the raw-HID config channel. Interfaces 0 and 2 carry
  # keystrokes, so widening this to the whole device would expose a keylog.
  configInterface = "01";
  # Atmel DFU bootloader IDs for the ATmega32U4 on the Hasu FC660C Alt Controller.
  dfuVendorId = "03eb";
  dfuProductId = "2ff4";

  keyboardModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.hardware.keyboards.fc660c;

      # Sort window is 61..72: 60-persistent-hidraw.rules sets the ID_USB_*
      # properties matched below, and 73-seat-late.rules is what acts on
      # TAG+="uaccess". services.udev.extraRules would write 99-local.rules.
      udevRules = pkgs.writeTextFile {
        name = "fc660c-udev-rules";
        destination = "/etc/udev/rules.d/70-vial-fc660c.rules";
        text = ''
          # ENV rather than ATTRS because udev requires every ATTRS key in a rule
          # to match one parent, and bInterfaceNumber sits on the interface while
          # serial sits on the device. uaccess alone, no MODE/GROUP: GROUP="users"
          # would let any local account read the raw HID stream.
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ENV{ID_USB_VENDOR_ID}=="${vendorId}", ENV{ID_USB_MODEL_ID}=="${productId}", ENV{ID_USB_SERIAL_SHORT}=="${vialSerial}", ENV{ID_USB_INTERFACE_NUM}=="${configInterface}", TAG+="uaccess"

          # Reflashing without root. hardware.keyboard.qmk.enable grants this too,
          # but its 50-qmk.rules also blankets every hidraw node at 0660 plugdev.
          SUBSYSTEMS=="usb", ATTRS{idVendor}=="${dfuVendorId}", ATTRS{idProduct}=="${dfuProductId}", TAG+="uaccess"
        '';
      };
    in
    {
      options.hardware.keyboards.fc660c = {
        enable = lib.mkEnableOption "Leopold FC660C (Hasu Alt Controller, Vial firmware): Vial GUI, udev access, and DFU reflash tooling";
      };

      config = lib.mkIf cfg.enable {
        # This bootloader speaks Atmel DFU; avrdude's protocols do not apply, and
        # the qmk CLI builds firmware rather than flashing an already-built image.
        environment.systemPackages = [
          pkgs.vial
          pkgs.dfu-programmer
        ];

        services.udev.packages = [ udevRules ];
      };
    };
in
{
  flake.nixosModules.hardware.keyboards.fc660c = keyboardModule;
  flake.nixosModules."hardware-fc660c" = keyboardModule;
}
