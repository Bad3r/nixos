{ lib, config, ... }:
{
  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          # Core system libraries
          glibc
          glib
          openssl
          nss
          nspr
          stdenv.cc.cc
          stdenv.cc.cc.lib
          zlib
          
          # Networking and communication
          curl
          dbus
          
          # Text and data processing
          icu
          libxml2
          libxslt
          
          # Graphics libraries
          freetype
          fontconfig
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
          xorg.libXtst
          
          # OpenGL/Vulkan/Graphics
          mesa
          libglvnd
          libva
          vulkan-loader
          libdrm
          libgbm
          
          # Audio
          alsa-lib
          cups
          
          # Other system libraries
          libxkbcommon
          expat
          systemd
        ] ++ lib.optionals (config.hardware.nvidia.modesetting.enable or false) [
          # NVIDIA-specific libraries when NVIDIA GPU is present
          config.hardware.nvidia.package
        ];
      };
      
      # Essential packages for VSCode Remote SSH functionality
      environment.systemPackages = with pkgs; [
        # Core utilities that VSCode Server expects
        bash
        gnutar
        curl
        wget
        git
        
        # Node.js for VSCode extensions
        nodejs_22
        
        # Build tools for native extensions
        gcc
        gnumake
        binutils
        coreutils
        gzip
        xz
        
        # Python for extensions that require it
        python3
        
        # Process management tools
        procps
        lsof
      ];
      
      # Environment variables for VSCode Server
      environment.variables = {
        VSCODE_SERVER_TAR = "${pkgs.gnutar}/bin/tar";
        NODE_PATH = "${pkgs.nodejs_22}/lib/node_modules";
      };
      
      # VSCode Server compatibility script
      environment.etc."vscode-server-fix.sh" = {
        text = ''
          #!/usr/bin/env bash
          # VSCode Server fix script for NixOS
          # This helps VSCode Server find the correct Node.js binary
          
          VSCODE_SERVER_DIR="$HOME/.vscode-server"
          
          if [ -d "$VSCODE_SERVER_DIR" ]; then
            echo "Fixing VSCode Server Node.js links..."
            
            # Find all node binaries in VSCode Server
            find "$VSCODE_SERVER_DIR" -name node -type f 2>/dev/null | while read -r node_path; do
              node_dir=$(dirname "$node_path")
              
              # Check if this is actually a VSCode Server node binary
              if [[ "$node_path" == *"/bin/"* ]]; then
                # Create a wrapper script
                mv "$node_path" "$node_path.original" 2>/dev/null || true
                cat > "$node_path" << EOF
          #!/usr/bin/env bash
          # Wrapper to use system Node.js if the bundled one fails
          if [ -f "\$(dirname "\$0")/node.original" ]; then
            "\$(dirname "\$0")/node.original" "\$@" 2>/dev/null || ${pkgs.nodejs_22}/bin/node "\$@"
          else
            ${pkgs.nodejs_22}/bin/node "\$@"
          fi
          EOF
                chmod +x "$node_path"
              fi
            done
            
            echo "VSCode Server fix applied successfully."
          else
            echo "VSCode Server directory not found. Run this script after connecting with VSCode Remote SSH."
          fi
        '';
        mode = "0755";
      };
      
      # Activation script to ensure Node.js is available in expected location
      system.activationScripts.vscodeServerCompat = lib.stringAfter [ "users" ] ''
        # Create common binary directory if it doesn't exist
        mkdir -p /run/current-system/sw/bin
        
        # Ensure node binary is available where VSCode Server might look for it
        if [ ! -e /run/current-system/sw/bin/node ]; then
          ln -sf ${pkgs.nodejs_22}/bin/node /run/current-system/sw/bin/node 2>/dev/null || true
        fi
        
        # Ensure npm is also available
        if [ ! -e /run/current-system/sw/bin/npm ]; then
          ln -sf ${pkgs.nodejs_22}/bin/npm /run/current-system/sw/bin/npm 2>/dev/null || true
        fi
      '';
    };
}