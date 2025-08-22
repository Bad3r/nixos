{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        gptfdisk
        dua
        ncdu
      ];
    };

  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        gparted
        parted
        nvme-cli
        smartmontools
        hdparm
        duf
        dust
        iotop
        kdiskmark
        testdisk
        ddrescue
        f3
        gnome-disk-utility
        ent
      ];

      services.smartd = {
        enable = true;
        notifications = {
          x11.enable = true;
          wall.enable = true;
        };
      };
    };
}
