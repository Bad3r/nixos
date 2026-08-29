_:
let
  # Vial hardcodes this serial on every Vial board so one rule matches all of them.
  vialSerial = "vial:f64c2b3c";
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

      # Must sort before systemd's 73-seat-late.rules, which is what acts on
      # TAG+="uaccess". services.udev.extraRules would write 99-local.rules.
      udevRules = pkgs.writeTextFile {
        name = "fc660c-udev-rules";
        destination = "/etc/udev/rules.d/59-vial-fc660c.rules";
        text = ''
          # Serial match is deliberate: pkgs.vial's own 92-viia.rules opens every
          # hidraw node at MODE=0666, so it stays out of services.udev.packages.
          KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*${vialSerial}*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"

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
