{ lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      security = {
        pam.sshAgentAuth.enable = true;
        polkit.enable = true;
        apparmor = {
          enable = true;
          killUnconfinedConfinables = true;
        };
      };

      environment.systemPackages =
        (with pkgs; [
          bitwarden-desktop
          bitwarden-cli
          keepassxc
          gopass
          gnupg
          gpg-tui
          pinentry-qt
          age
          sops
          ssh-to-age
          ssh-to-pgp
          openssh
          mosh
          sshfs
          ssh-audit
          nmap
          wireshark
          tcpdump
          netcat
          socat
          openvpn
          wireguard-tools
          cryptsetup
          lynis
          vt-cli
          yubico-piv-tool
          yubikey-manager
          yubikey-personalization
          iptables
          nftables
          pwgen
          xkcdpass
          hashcat
          # TODO(#43): Re-enable when john builds with GCC 15
          # See: https://github.com/openwall/john/issues/2180
          # john
          foremost
          testdisk
          tor
          certbot
          mkcert
        ])
        ++ [ pkgs.age-plugin-fido2prf ];

      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        pinentryPackage = lib.mkForce pkgs.pinentry-qt;
      };

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ ];
        allowedUDPPorts = [ ];
      };

      services.fail2ban = {
        enable = true;
        maxretry = 3;
        bantime = "1h";
        bantime-increment = {
          enable = true;
          maxtime = "48h";
        };
      };

      services.clamav = {
        daemon.enable = false;
        updater.enable = false;
      };

    };
}
