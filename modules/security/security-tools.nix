{
  flake.nixosModules.workstation =
    { pkgs, lib, ... }:
    {
      # Enable PAM ssh-agent authentication support system-wide.
      security.pam.sshAgentAuth.enable = true;

      # Security tools are workstation features
      environment.systemPackages = with pkgs; [
        # Password managers
        bitwarden-desktop
        bitwarden-cli
        keepassxc
        gopass

        # GPG and encryption
        gnupg
        gpg-tui
        pinentry-qt
        age
        sops
        ssh-to-age
        ssh-to-pgp

        # SSH tools
        openssh
        mosh
        sshfs
        ssh-audit

        # Network security
        nmap
        wireshark
        tcpdump
        netcat
        socat

        # VPN
        openvpn
        wireguard-tools

        # File encryption
        cryptsetup
        # veracrypt  # Disabled: unfree license issue

        # Security scanners
        lynis
        vt-cli # VirusTotal Command Line Interface

        # Authentication
        yubico-piv-tool
        yubikey-manager
        yubikey-personalization

        # Firewall management
        iptables
        nftables

        # Password generation
        pwgen
        xkcdpass

        # Hash tools
        hashcat
        john

        # Forensics
        foremost
        testdisk # includes photorec

        # Privacy tools
        tor
        # Note: tor-browser is available in home/gui/tor-browser.nix for GUI users

        # Certificate management
        certbot
        mkcert
      ];

      # GPG configuration
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        pinentryPackage = lib.mkForce pkgs.pinentry-qt;
      };

      # Firewall configuration
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ ];
        allowedUDPPorts = [ ];
      };

      # Security-related services
      services = {
        # Fail2ban for SSH protection
        fail2ban = {
          enable = true;
          maxretry = 3;
          bantime = "1h";
          bantime-increment = {
            enable = true;
            maxtime = "48h";
          };
        };

        # ClamAV antivirus
        clamav = {
          daemon.enable = false; # Enable if needed
          updater.enable = false; # Enable if needed
        };
      };

      # Security hardening
      security = {
        # sudo-rs is configured in sudo.nix module

        # Polkit configuration
        polkit.enable = true;

        # Enable AppArmor
        apparmor = {
          enable = true;
          killUnconfinedConfinables = true;
        };
      };
    };
}
