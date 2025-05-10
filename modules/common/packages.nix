# modules/common/packages.nix
# List packages installed in system profile. To search, run:
# $ nix search wget
{
  config,
  pkgs,
  lib,
  ...
}:

let
  common = with pkgs; [
    dash
    python3
    neovim
    evil-helix # Helix with evil-mode (https://github.com/danymat/evil-helix)
    git
    tree
    eza # exa maintained fork (https://github.com/eza-community/eza)
    bash-language-server
    zip
    unzip
    rar
    unrar
    p7zip-rar # supports extracting rar files
    nil # Nix Language server
    nixfmt-rfc-style # new RFC will be replaced with nixfmt in the future
    nixfmt-tree # treefmt for Nix (https://treefmt.com/)
    niv # Dependency manager for Nix  (https://github.com/nmattia/niv)
    bat
    ripgrep
    fd
    tealdeer
    gnupg
    openssl
    aspell
    font-awesome
    eva
    biome
    bitwarden-desktop
    bottom
    catdoc
    dua
    duf
    diffutils
    fzf
    ghostscript
    ffmpeg
    ffmpegthumbnailer
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-vaapi
    htop
    hunspell
    hunspellDicts.en-us-large
    jq # JSON processor
    jq-lsp # jq language server
    jq-zsh-plugin # Interactively build jq expressions in Zsh
    jnv # Interactive JSON filter using jq
    htmlq # jq for HTML
    xq # jq for XML
    yq # jq wrapper for YAML, XML, TOML
    fq # jq for binary formats
    imagemagick
    ghostty # Terminal emulator
    kitty # Terminal emulator
    less # More advanced file pager than 'more'
    meld # Visual diff and merge tool
    shfmt

  ];

  linuxPkgs = with pkgs; [
    pciutils
    nemo
    ntfs3g
    file
    pipewire
    protonvpn-gui
    blueberry
    arandr
    xdg-utils
    dmenu
    dunst
    rofi
    docker
    docker-compose
    dosfstools
    efitools
    exiftool
    electron
    keepassxc
    ethtool
    zathura
    mupdf-headless # Lightweight PDF, XPS, and E-book viewer and toolkit
    feh
    flameshot
    fwupd
    gparted
    gvfs
    hdparm
    hddtemp
    hsetroot
    hwinfo
    i3
    i3status-rust
    i3lock-fancy
    autotiling
    libnotify
    networkmanager
    networkmanager_dmenu
    networkmanager-openvpn
    networkmanager-openconnect
    networkmanagerapplet
    inetutils
    iproute2
    iputils
    iwd
    inotify-tools
    linux-firmware
    linuxHeaders
    lsb-release # Prints certain LSB (Linux Standard Base) and Distribution information
    lm_sensors # Tools for reading hardware sensors
    lsof # List open files
    logrotate # Rotates and compresses system logs
    lsscsi # List SCSI devices
    maim # Command-line screenshot utility
    man # Linux manual pages
    man-pages # Linux development manual pages
    ntpd-rs # NTP daemon
    ntpstat # NTP status
    nwg-look # GTK3 settings editor
    libplacebo # Video rendering library
    libva # Video acceleration API
    libva-utils # Video acceleration utilities
    libvirt # Virtualization API

  ];

  darwinPkgs = with pkgs; [
    mas
    homebrew
  ];
in
{
  environment.systemPackages =
    common
    ++ (lib.optionals config.nixpkgs.hostPlatform.isLinux linuxPkgs)
    ++ (lib.optionals config.nixpkgs.hostPlatform.isDarwin darwinPkgs);
}
