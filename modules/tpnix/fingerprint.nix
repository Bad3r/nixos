{ lib, ... }:
let
  fingerprintPamServices = [
    "i3lock"
    "i3lock-color"
    "lightdm"
    "login"
    "polkit-1"
    "su"
    "su-l"
    "sudo"
    "sudo-i"
  ];

  nonFingerprintPamServices = [
    "chfn"
    "chpasswd"
    "chsh"
    "groupadd"
    "groupdel"
    "groupmems"
    "groupmod"
    "lightdm-autologin"
    "lightdm-greeter"
    "other"
    "passwd"
    "runuser"
    "runuser-l"
    "sshd"
    "systemd-run0"
    "systemd-user"
    "useradd"
    "userdel"
    "usermod"
    "vlock"
    "xlock"
    "xscreensaver"
  ];
in
{
  configurations.nixos.tpnix.module = {
    services.fprintd = {
      enable = true;
      tod.enable = false;
    };

    security.pam.services =
      lib.genAttrs fingerprintPamServices (_name: {
        fprintAuth = lib.mkForce true;
      })
      // lib.genAttrs nonFingerprintPamServices (_name: {
        fprintAuth = lib.mkForce false;
      });
  };
}
