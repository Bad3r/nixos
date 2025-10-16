_: {
  nixpkgs.allowedUnfreePackages = [
    "system76-wallpapers"
    "system76-wallpapers-0-unstable-2024-04-26"
    "nvidia-x11"
    "nvidia-settings"
    "p7zip-rar"
    "rar"
    "unrar"
  ];

  configurations.nixos.system76.module = _: { };
}
