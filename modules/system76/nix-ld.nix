{ config, lib, ... }:
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      programs.nix-ld = {
        enable = true;
        libraries =
          with pkgs;
          [
            glibc
            glib
            openssl
            nss
            nspr
            stdenv.cc.cc
            stdenv.cc.cc.lib
            zlib
            curl
            dbus
            icu
            libxml2
            libxslt
            freetype
            fontconfig
            gtk3
            gdk-pixbuf
            pango
            cairo
            atk
            at-spi2-core
            at-spi2-atk
            libx11
            libxrandr
            libxext
            libxfixes
            libxcomposite
            libxdamage
            libxcb
            libxshmfence
            libxxf86vm
            libxv
            libxinerama
            libxtst
            libxi
            libxcursor
            mesa
            libglvnd
            libva
            vulkan-loader
            libdrm
            libgbm
            alsa-lib
            libpulseaudio # PulseAudio client library (works with pipewire-pulse)
            # Android emulator dependencies (from nixpkgs/pkgs/development/mobile/androidenv/emulator.nix)
            libcxx
            libtiff
            libuuid
            libbsd
            ncurses5
            libxrender
            libice
            libsm
            libxkbfile
            libpng
            libjpeg
            libwebp
            snappy
            SDL2
            cups
            libxkbcommon
            expat
            systemd
          ]
          ++ lib.optionals (config.hardware.nvidia.modesetting.enable or false) [
            config.hardware.nvidia.package
          ];
      };

      environment = {
        systemPackages = with pkgs; [
          bash
          gnutar
          curl
          wget
          git
          nodejs_24
          gcc
          gnumake
          binutils
          coreutils
          gzip
          xz
          python3
          procps
          lsof
        ];

        variables = {
          VSCODE_SERVER_TAR = "${pkgs.gnutar}/bin/tar";
          NODE_PATH = "${pkgs.nodejs_24}/lib/node_modules";
        };

        etc."vscode-server-fix.sh" = {
          text = ''
            #!/usr/bin/env bash
            # VSCode Server fix script for NixOS
            # This helps VSCode Server find the correct Node.js binary

            VSCODE_SERVER_DIR="$HOME/.vscode-server"

            set -euo pipefail

            if [ -d "$VSCODE_SERVER_DIR" ]; then
              echo "Fixing VSCode Server Node.js links..."

              find "$VSCODE_SERVER_DIR" -name node -type f 2>/dev/null | while read -r node_path; do
                node_dir=$(dirname "$node_path")

                if [[ "$node_path" == *"/bin/"* ]]; then
                  backup="$node_path.original"
                  if [ ! -e "$backup" ]; then
                    if ! mv "$node_path" "$backup"; then
                      echo "Failed to back up $node_path" >&2
                      exit 1
                    fi
                  fi
                  cat > "$node_path" << EOF
            #!/usr/bin/env bash
            # Wrapper to use system Node.js if the bundled one fails
            if [ -f "\$(dirname "\$0")/node.original" ]; then
              "\$(dirname "\$0")/node.original" "\$@" 2>/dev/null || ${pkgs.nodejs_24}/bin/node "\$@"
            else
              ${pkgs.nodejs_24}/bin/node "\$@"
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
      };
    };
}
