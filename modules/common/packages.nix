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
    aspell
    bash-language-server
    bat
    biome
    bitwarden-desktop
    bottom
    pandoc
    dash
    diffutils
    dua
    duf
    eva
    evil-helix # Helix with evil-mode (https://github.com/danymat/evil-helix)
    eza # exa maintained fork (https://github.com/eza-community/eza)
    fd
    ffmpeg
    ffmpegthumbnailer
    font-awesome
    fq # jq for binary formats
    fzf
    ghostscript
    ghostty # Terminal emulator
    git
    gnupg
    gst_all_1.gst-libav
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-vaapi
    htmlq # jq for HTML
    htop
    hunspell
    hunspellDicts.en-us-large
    imagemagick
    jnv # Interactive JSON filter using jq
    jq # JSON processor
    jq-lsp # jq language server
    jq-zsh-plugin # Interactively build jq expressions in Zsh
    kitty # Terminal emulator
    less # More advanced file pager than \'more\'
    meld # Visual diff and merge tool
    neovim
    nil # Nix Language server
    niv # Dependency manager for Nix  (https://github.com/nmattia/niv)
    nixfmt-rfc-style # new RFC will be replaced with nixfmt in the future
    nixfmt-tree # treefmt for Nix (https://treefmt.com/)
    openssl
    p7zip-rar # supports extracting rar files
    python3
    rar
    ripgrep
    shfmt
    tealdeer
    tree
    unrar
    unzip
    xq # jq for XML
    yq # jq wrapper for YAML, XML, TOML
    zip

  ];

  linuxPkgs = with pkgs; [
    arandr
    autotiling
    blueberry
    dmenu
    docker
    docker-compose
    dosfstools
    dunst
    efitools
    electron
    ethtool
    exiftool
    feh
    file
    flameshot
    fwupd
    gparted
    gvfs
    hddtemp
    hdparm
    hsetroot
    hwinfo
    i3
    i3lock-fancy
    i3status-rust
    inetutils
    inotify-tools
    iproute2
    iputils
    iwd
    keepassxc
    libnotify
    libplacebo # Video rendering library
    libva # Video acceleration API
    libva-utils # Video acceleration utilities
    libvirt # Virtualization API
    linux-firmware
    linuxHeaders
    lm_sensors # Tools for reading hardware sensors
    logrotate # Rotates and compresses system logs
    lsof # List open files
    lsb-release # Prints certain LSB (Linux Standard Base) and Distribution information
    lsscsi # List SCSI devices
    maim # Command-line screenshot utility
    man # Linux manual pages
    man-pages # Linux development manual pages
    mupdf-headless # Lightweight PDF, XPS, and E-book viewer and toolkit
    nemo
    networkmanager
    networkmanager_dmenu
    networkmanager-openconnect
    networkmanager-openvpn
    networkmanagerapplet
    ntfs3g
    ntpd-rs # NTP daemon
    ntpstat # NTP status
    nwg-look # GTK3 settings editor
    pciutils
    pipewire
    protonvpn-gui
    rofi
    xdg-utils
    zathura
  ];

  darwinPkgs = with pkgs; [
    homebrew
    mas
  ];
in
{
  environment.systemPackages =
    common
    ++ (lib.optionals config.nixpkgs.hostPlatform.isLinux linuxPkgs)
    ++ (lib.optionals config.nixpkgs.hostPlatform.isDarwin darwinPkgs);
}
