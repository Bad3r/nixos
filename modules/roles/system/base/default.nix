{
  config,
  lib,
  ...
}:
let
  helpers = config._module.args.nixosAppHelpers or { };
  rawHelpers = (config.flake.lib.nixos or { }) // helpers;
  fallbackGetApp =
    name:
    if lib.hasAttrByPath [ "apps" name ] config.flake.nixosModules then
      lib.getAttrFromPath [ "apps" name ] config.flake.nixosModules
    else
      throw ("Unknown NixOS app '" + name + "' (role system.base)");
  getApp = rawHelpers.getApp or fallbackGetApp;
  getApps = rawHelpers.getApps or (names: map getApp names);

  baseModule =
    if lib.hasAttrByPath [ "base" ] config.flake.nixosModules then
      lib.getAttrFromPath [ "base" ] config.flake.nixosModules
    else
      throw "flake.nixosModules.base missing while constructing roles.system.base";

  baseApps = [
    "coreutils"
    "util-linux"
    "procps"
    "psmisc"
    "less"
    "diffutils"
    "patch"
    "file"
    "findutils"
    "gawk"
    "gnugrep"
    "gnused"
    "rip2"
    "which"
    "xsel"
    "git"
    "bash-completion"
    "zsh-completions"
    "starship"
    "zoxide"
    "atuin"
    "bc"
    "openssl"
    "lsof"
    "pciutils"
    "usbutils"
    "lshw"
    "dmidecode"
  ];
  baseExtensionApps = [
    "accountsservice"
    "acl"
    "adwaita-icon-theme"
    "age"
    "age-plugin-fido2prf"
    "appimage-run"
    "attr"
    "getconf-glibc"
    "getent-glibc"
    "gnutar"
    "ld-library-path"
    "audit"
    "bash-interactive"
    "bcache-tools"
    "bind"
    "binutils-wrapper"
    "btrfs-progs"
    "certbot"
    "coreutils-full"
    "command-not-found"
    "cpio"
    "cryptsetup"
    "dash"
    "dbus"
    "dconf"
    "dosfstools"
    "du-dust"
    "e2fsprogs"
    "fontconfig"
    "foremost"
    "fuse"
    "fwupd"
    "gcc-wrapper"
    "ghostscript-with-X"
    "glib"
    "glibc"
    "glibc-locales"
    "gsettings-desktop-schemas"
    "hicolor-icon-theme"
    "hostname-debian"
    "iotop"
    "iproute2"
    "iptables"
    "iputils"
    "iwd"
    "kbd"
    "kexec-tools"
    "kmod"
    "libcap"
    "libressl"
    "libva-utils"
    "linux-pam"
    "lvm2"
    "man-db"
    "mkcert"
    "mkpasswd"
    "modemmanager"
    "mtools"
    "ncurses"
    "nix"
    "nix-bash-completions"
    "nix-info"
    "nix-zsh-completions"
    "nftables"
    "nmap"
    "openssh"
    "openssl"
    "perl"
    "pkg-config-wrapper"
    "plocate"
    "polkit"
    "tcpdump"
    "texinfo-interactive"
    "python3"
    "shadow"
    "shared-mime-info"
    "systemd"
    "time"
    "tlp"
    "tumbler"
    "udisks"
    "upower"
    "usbguard"
    "usbutils"
    "util-linux"
    "xfsprogs"
    "xdg-utils"
    "zsh-forgit"
    "zsh"
  ];

  allBaseApps = baseApps ++ baseExtensionApps;
  roleImports = [ baseModule ] ++ getApps allBaseApps;
in
{
  flake.nixosModules.roles.system.base = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" ];
      auxiliaryCategories = [ ];
      secondaryTags = [ ];
    };
    imports = roleImports;
  };
}
