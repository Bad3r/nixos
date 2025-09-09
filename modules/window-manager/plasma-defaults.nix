{
  flake.modules.nixos.pc =
    { pkgs, lib, ... }:
    {
      # Provide a curated baseline of KDE apps/utilities; later roles/users can extend/override
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          kdePackages.kate
          kdePackages.kdenlive
          kdePackages.ark
          kdePackages.okular
          kdePackages.gwenview
          kdePackages.spectacle
          kdePackages.kcalc
          kdePackages.kcolorchooser
          kdePackages.partitionmanager
          kdePackages.kdeconnect-kde
          kdePackages.filelight
          kdePackages.kdf
          kdePackages.kcharselect
          kdePackages.kfind
          kdePackages.kruler
          kdePackages.kwalletmanager
          kdePackages.ktimer
          kdePackages.sweeper
          kdePackages.kdialog
          kdePackages.breeze-gtk
          kdePackages.breeze-icons
          kdePackages.plasma-systemmonitor
          kdePackages.ksystemlog
          kdePackages.yakuake
          kdePackages.kdeplasma-addons
        ]
      );
    };
}
