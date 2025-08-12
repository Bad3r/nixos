
{ ... }:
{
  flake.modules.nixos.workstation = { pkgs, ... }: {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # Basic libraries
        glib
        openssl
        nss
        nspr
        stdenv.cc.cc
        zlib
        
        # DBus
        dbus
        
        # Graphics libraries
        gtk3
        gdk-pixbuf
        pango
        cairo
        atk
        at-spi2-core
        at-spi2-atk
        
        # X11 libraries
        xorg.libX11
        xorg.libXrandr
        xorg.libXext
        xorg.libXfixes
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libxcb
        xorg.libxshmfence
        xorg.libXxf86vm
        xorg.libXv
        xorg.libXinerama
        
        # OpenGL/Vulkan
        mesa
        libglvnd
        libva
        vulkan-loader
        libdrm
        
        # Audio
        alsa-lib
        cups
        
        # Other
        libxkbcommon
        expat
        systemd
      ];
    };
  };
}