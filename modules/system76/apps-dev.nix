{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

  devAppNames = [
    # editors and viewers
    "neovim"
    "vim"
    "glow"
    # build tools
    "cmake"
    "gcc"
    "gnumake"
    "pkg-config"
    "formatting"
    # JSON/YAML and inspection
    "jq"
    "yq"
    "jnv"
    "tokei"
    "hyperfine"
    "git-filter-repo"
    "forgit"
    "exiftool"
    "yaak"
    # debugging and tracing
    "gdb"
    "valgrind"
    "strace"
    "ltrace"
    "ent"
    # reverse engineering
    "ghidra"
    "radare2"
    "rizin"
    "cutter"
    "iaito"
    # Node toolchains and managers
    "nodejs_24"
    "nodejs_22"
    "yarn"
    "nrm"
    # FHS-based dev environments
    "vscode-fhs"
    "kiro-fhs"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps devAppNames;
}
