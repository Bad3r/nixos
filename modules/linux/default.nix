# modules/linux/default.nix
{ pkgs, ... }:

{
  imports = [
    ./hardware/bluetooth.nix
    ./services/dbus.nix
    ./hardware/pipewire.nix
    ./services/xserver.nix
  ];
  # Systemd-boot configuration
  boot.loader = {
    efi.canTouchEfiVariables = true; # Allow EFI variable modification
    systemd-boot = {
      enable = true;
      editor = false; # Disable editing of boot entries
      consoleMode = "auto"; # Automatic console mode detection
      configurationLimit = 3; # Keep only last N generations
    };
  };
  boot.initrd.compressor = "zstd";

  security.polkit.enable = true;

  # Networking
  # systemd.network.enable = true;
  # networking.useNetworkd = true;
  networking.networkmanager.enable = true;
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # XDG
  xdg.menus.enable = true;
  xdg.mime.enable = true;
  # xdg.mime.defaultApplications = {
  # };

  # Some programs need SUID wrappers, can be configured further or are started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    enableExtraSocket = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Security
  security.rtkit.enable = true;

  # services
  services.printing.enable = false;
  # Enable the OpenSSH daemon (server)
  services.openssh.enable = false;

  # Shell
  environment.shells = with pkgs; [
    # bash
    dash
    # fish
    # zsh
  ];
  # /bin/sh -> /bin/dash
  environment.binsh = "${pkgs.dash}/bin/dash";

  # Global user settings
  # Allow password changes
  users.mutableUsers = true;
  # Set default shell
  users.defaultUserShell = pkgs.zsh;

  # PAM configuration
  #   security.pam.services = {
  #     login.allowNullPassword = true; # to enable setting user password on first-login
  #     sudo.allowNullPassword = false;
  #     sshd.allowNullPassword = false;
  #   };

  # SSH/gnupg
  programs.ssh.extraConfig = ''
    IdentityAgent /run/user/%i/gnupg/S.gpg-agent.ssh
  '';
  environment.variables = {
    OPENSSL_CONF = "/etc/ssl/openssl.cnf";
  };
}
