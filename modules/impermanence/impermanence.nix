{
  inputs,
  lib,
  config,
  ...
}:
{
  flake.modules.nixos.impermanence = {
    imports = [ inputs.impermanence.nixosModules.impermanence ];

    environment.persistence."/persist" = lib.mkIf (config.boot.impermanence.enable or false) {
      hideMounts = true;

      # System directories to persist
      directories = [
        "/etc/nixos"
        "/etc/NetworkManager/system-connections"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
        "/var/lib/flatpak"
        "/var/lib/libvirt"
        "/var/lib/docker"
        "/var/lib/podman"
        "/var/lib/lxd"
        "/var/lib/sops-nix"
        "/var/log"
        "/var/lib/cups"
        "/var/cache/cups"
      ];

      # System files to persist
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];

      # User persistence
      users.vx = {
        directories = [
          ".cache"
          ".config"
          ".local"
          ".mozilla"
          ".ssh"
          ".gnupg"
          "Documents"
          "Downloads"
          "Music"
          "Pictures"
          "Videos"
          "Projects"
          ".vscode"
          ".vscode-server"
          ".nixops"
          ".aws"
          ".kube"
          ".docker"
          ".npm"
          ".cargo"
          ".rustup"
          ".java"
          ".gradle"
          ".m2"
          ".sbt"
          ".ivy2"
          ".stack"
          ".cabal"
          ".ghcup"
          ".nix-defexpr"
          ".nix-profile"

          # KDE Plasma persistence
          ".kde"
          ".kde4"
          ".local/share/plasma"
          ".local/share/kwalletd"
          ".local/share/kscreen"
          ".local/share/konsole"
          ".local/share/dolphin"
          ".local/share/kate"
          ".local/share/okular"
          ".local/share/ark"
          ".local/share/klipper"
          ".local/share/knotes"
          ".local/share/kontact"
          ".local/share/kmail2"
          ".local/share/akonadi"
          ".local/share/baloo"
          ".config/kde.org"
          ".config/plasma-workspace"
          ".config/plasmashellrc"
          ".config/kdeglobals"
          ".config/kwinrc"
          ".config/ksmserverrc"
          ".config/kglobalshortcutsrc"
          ".config/khotkeysrc"
          ".config/systemsettingsrc"
          ".config/dolphinrc"
          ".config/konsolerc"
          ".config/katerc"
          ".config/okularrc"
          ".config/spectaclerc"
          ".config/klipperrc"
          ".config/krunnerrc"
          ".config/kscreenlockerrc"
          ".config/kwalletrc"
          ".config/kmixrc"
          ".config/powerdevilrc"
          ".config/kded5rc"
          ".config/kdialogrc"
          ".config/kioslaverc"
          ".config/knotifyrc"
          ".config/ktimezonedrc"
          ".config/plasma-org.kde.plasma.desktop-appletsrc"

          # Application data
          ".thunderbird"
          ".zoom"
          ".steam"
          ".local/share/Steam"
          ".minecraft"
          ".factorio"
          ".local/share/JetBrains"
          ".local/share/virtualbox"
          ".local/share/libvirt"
          ".local/share/containers"
          ".local/share/flatpak"
          ".local/share/Trash"
          ".local/share/applications"
          ".local/share/desktop-directories"
          ".local/share/icons"
          ".local/share/fonts"
          ".local/share/themes"
          ".local/share/color-schemes"
          ".local/share/wallpapers"

          # Development
          ".gitconfig"
          ".git-credentials"
          "nixos"
          "work"
          "dev"
          "workspace"
        ];

        files = [
          ".bash_history"
          ".zsh_history"
          ".lesshst"
          ".wget-hsts"
          ".node_repl_history"
          ".python_history"
        ];
      };
    };

    # Boot configuration for impermanence
    boot.impermanence = lib.mkIf (config.boot.impermanence.enable or false) {
      # Clear root on boot
      initrd.postDeviceCommands = lib.mkAfter ''
        mkdir -p /mnt

        # Mount the root filesystem
        mount -o subvol=/ /dev/mapper/crypted /mnt

        # Delete everything except persist subvolume
        btrfs subvolume list -o /mnt | cut -f9 -d' ' |
        while read subvolume; do
          echo "Deleting /$subvolume subvolume..."
          btrfs subvolume delete "/mnt/$subvolume"
        done &&
        echo "Deleting files from root subvolume..." &&
        find /mnt -mindepth 1 -maxdepth 1 ! -name persist -exec rm -rf {} +

        umount /mnt
      '';
    };

    # Ensure /persist exists
    fileSystems."/persist" = lib.mkIf (config.boot.impermanence.enable or false) {
      device = "/dev/mapper/crypted";
      fsType = "btrfs";
      options = [
        "subvol=persist"
        "compress=zstd"
        "noatime"
      ];
      neededForBoot = true;
    };

    # Create a systemd service to handle bind mounts for impermanence
    systemd.services.impermanence-bind-mounts = lib.mkIf (config.boot.impermanence.enable or false) {
      description = "Create bind mounts for impermanence";
      wantedBy = [ "multi-user.target" ];
      before = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Ensure persist directories exist
        mkdir -p /persist/system
        mkdir -p /persist/home
      '';
    };
  };
}
