# Building Logseq on NixOS with FHS Environment

This guide documents how to build Logseq from source on NixOS using an FHS (Filesystem Hierarchy Standard) environment, which provides a traditional Linux filesystem layout that Logseq's build process expects.

## Why FHS?

Logseq has a complex build process with:

- 7 separate `yarn.lock` files across multiple workspaces
- 37,000+ lines of JavaScript dependencies
- Mixed technology stack (ClojureScript, React, Electron)
- Native build dependencies

Packaging this properly in Nix requires tracking all dependency hashes and is extremely complex. The FHS approach sidesteps this by providing a traditional build environment.

## The FHS Build Environment

Create a file `logseq-build-env.nix`:

```nix
{ pkgs }:

pkgs.buildFHSEnv {
  name = "logseq-build";

  targetPkgs = pkgs: with pkgs; [
    # Build tools
    yarn nodejs_20 clojure git

    # System tools
    coreutils gnused findutils which

    # For electron builds
    electron libnotify

    # Libraries that Node modules might need
    python3 gnumake gcc
    glib nss nspr atk cups dbus expat libdrm
    xorg.libX11 xorg.libXcomposite xorg.libXdamage
    xorg.libXext xorg.libXfixes xorg.libXrandr xorg.libxcb
    pango cairo alsa-lib at-spi2-atk at-spi2-core

    # For extracting AppImage
    libarchive
  ];

  multiPkgs = pkgs: with pkgs; [
    zlib glibc
  ];

  runScript = "bash";

  profile = ''
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    export ELECTRON_OVERRIDE_DIST_PATH=${pkgs.electron}/bin
    export NODE_OPTIONS="--max-old-space-size=8192"

    echo "FHS Environment for Logseq build ready!"
    echo "To build Logseq:"
    echo "  cd ~/git/logseq"
    echo "  ~/dotfiles/bin/sss-update-logseq"
  '';
}
```

## Integrating with Flake

Add to your `flake.nix`:

```nix
packages = eachSystem (pkgs: {
  logseq-build-env = import ./logseq-build-env.nix { inherit pkgs; };
});

devShells = eachSystem (pkgs: {
  logseq-build-env = self.packages.${pkgs.system}.logseq-build-env.env;
});
```

## Build Script

The `sss-update-logseq` script handles the actual build. Key modifications for NixOS:

1. **Install to user directory**: Use `~/.local/opt/` instead of `/opt/`
2. **No sudo required**: All operations in user space
3. **Create desktop entry**: Automatically creates `.desktop` file

Key script sections:

```bash
# Configuration
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/opt/logseq-desktop-git}"

# Installation (no sudo)
mkdir -p "$(dirname "$INSTALL_DIR")"
rm -rf "$INSTALL_DIR"
mv squashfs-root "$INSTALL_DIR"

# Desktop entry
cat > "$HOME/.local/share/applications/logseq-custom.desktop" << EOF
[Desktop Entry]
Name=Logseq (Custom Build)
Exec=$INSTALL_DIR/Logseq %U
Terminal=false
Type=Application
Icon=$INSTALL_DIR/resources/app/icons/logseq.png
Categories=Office;
MimeType=x-scheme-handler/logseq;
EOF
```

## Building Logseq

1. Enter the FHS environment:

   ```bash
   nix run ~/nixos#logseq-build-env
   ```

2. Inside the environment, run the build script:

   ```bash
   cd ~/git/logseq
   ~/dotfiles/bin/sss-update-logseq
   ```

3. The script will:
   - Pull latest changes from `test/db` branch
   - Install all yarn dependencies
   - Build ClojureScript
   - Package as Electron app
   - Extract AppImage to `~/.local/opt/logseq-desktop-git/`
   - Create desktop entry

## Running Logseq

After building:

- **From terminal**: `~/.local/opt/logseq-desktop-git/Logseq`
- **From launcher**: Look for "Logseq (Custom Build)"

Note: The binary is named `Logseq` with a capital L.

## Updating

To check for updates:

```bash
cd ~/git/logseq
git fetch origin test/db
```

If updates are available, rebuild using the same process.

## Alternative Approaches Considered

1. **Pure Nix packaging**: Requires maintaining SHA256 hashes for 7+ yarn workspaces
2. **yarn2nix**: Struggles with multi-workspace projects
3. **dream2nix**: Modern approach but still complex for Logseq's structure
4. **Binary releases**: Using AppImage/Flatpak directly

The FHS approach provides the best balance of control and simplicity for development builds.
