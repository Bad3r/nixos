# hosts/linux/system76/default.nix
{ inputs, pkgs, ... }: {
  system.stateVersion = "24.11";
  networking.hostName = "system76";

  imports = [
    ../../../modules/linux/desktop/kde.nix
    ../../../modules/linux/hardware/nvidia.nix
    ../../../modules/linux/hardware/bluetooth.nix
    ./hardware.nix # overrides ../../ hardware-configuration.nix
    ./packages.nix # host‑specific packages
    inputs.impermanence.nixosModules.impermanence
  ];

  # Explicit user definition with null password
  users.users.vx = {
    isNormalUser = true;
    isSystemUser = false;
    home = "/home/vx";
    extraGroups = [ "wheel" "networkmanager" "video" "render" "input" ];
    initialPassword = null;
    hashedPassword = null;
    hashedPasswordFile = null;
    cryptHomeLuks = null;
    ignoreShellProgramCheck = false;
    useDefaultShell = true;
    openssh = {
      authorizedKeys = {
        keyFiles = [ ];
        keys = [ ];
      };
      authorizedPrincipals = [ ];
    };
    packages = [ ];
  };

  home-manager.users.vx = {
    imports = [ inputs.plasma-manager.homeManagerModules.plasma-manager ];

    programs.plasma = {
      enable = true;
      workspace = {
        lookAndFeel = "org.kde.breezedark.desktop";
        # Add additional workspace configurations here
      };
      # Add other plasma-manager configurations as needed
    };
  };

  # Set password on first-login
  #   system.activationScripts.forcePasswordChange = let
  #     chage = "${pkgs.shadow}/bin/chage";
  #   in ''
  #     ${pkgs.shadow}/bin/chage -d 0 vx
  #   '';

  # TODO: replace with `buildFHSUserEnv` or package logseq/test/db branch
  programs.nix-ld.enable = true;

  programs.nix-ld.libraries = with pkgs; [

    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages

    glib # GLib (libglib-2.0)
    openssl # OpenSSL (libssl)
    nss # NSS (libnss3)
    nspr # NSPR (libnspr4)
    dbus # D-Bus (libdbus-1)
    atk # ATK (libatk-1.0)
    at-spi2-core # AT-SPI2 (libatspi)
    at-spi2-atk # AT-SPI2 (libatspi)
    cups # CUPS (libcups)
    gtk3 # GTK+ 3 (libgtk-3)
    gdk-pixbuf # GdkPixbuf (libgdk_pixbuf-2.0)
    pango # Pango (libpango-1.0)
    cairo # Cairo (libcairo)
    xorg.libX11 # X11 (libX11)
    xorg.libXrandr # libXrandr.so.2
    xorg.libXext # libXext.so.6
    xorg.libXfixes # libXfixes.so.3
    xorg.libXcomposite # libXcomposite.so.1
    xorg.libXdamage # libXdamage.so.1
    xorg.libxcb # libxcb.so.1
    xorg.libxshmfence # libxshmfence.so.1
    xorg.libXxf86vm # libXxf86vm.so.1
    xorg.libXv # libXv.so.1
    xorg.libXinerama # libXinerama.so.1
    mesa # libgbm.so.1
    nvidia-vaapi-driver # libva.so.2
    libglvnd # libGL.so.1
    vaapiVdpau # libva.so.2
    libva # libva.so.2
    libva-utils # libva.so.2
    vulkan-loader # libvulkan.so.1
    vulkan-validation-layers # libvulkan.so.1
    libdrm # libdrm.so.2
    libgbm # libgbm.so.1
    alsa-lib # libasound.so.2
    libxkbcommon # libxkbcommon.so.0
    expat # libexpat.so.1
    systemd # libsystemd.so.0
  ];

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "logseq" ''
      # Library paths for Mesa components
      export LD_LIBRARY_PATH=${
        pkgs.lib.makeLibraryPath [
          pkgs.mesa # Contains libgbm and mesa_gbm.so
          pkgs.libgbm # Graphics Buffer Manager
          pkgs.libdrm # Direct Rendering Manager
          pkgs.xorg.libX11 # X11 support
          pkgs.xorg.libxcb # XCB library
        ]
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      # Force X11 platform for compatibility
      export ELECTRON_OZONE_PLATFORM_HINT="x11"
      export EGL_PLATFORM="x11"

      # Ensure GBM path is explicitly set
      export GBM_PATH="${pkgs.mesa}/lib/gbm/mesa_gbm.so"

      # Run Logseq with debug logging
      exec /home/vx/git/logseq/static/out/Logseq-linux-x64/Logseq "$@"
    '')
  ];
}
