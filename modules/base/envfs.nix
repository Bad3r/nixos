_: {
  flake.nixosModules.base = {
    services.envfs.enable = true;

    # Make envfs resolve entries for stat/readdir-style probes so FHS compatibility
    # works for tools that inspect /bin and /usr/bin instead of only execing paths.
    environment.variables.ENVFS_RESOLVE_ALWAYS = "1";

    # Pin envfs to 1.2.0 until nixpkgs PR #500707 lands. 1.1.0 exits its mount
    # helper before the FUSE mount is visible in /proc/self/mountinfo, so systemd
    # logs usr-bin.mount as `result=protocol` even though the mount succeeds.
    # Fixed upstream in Mic92/envfs#216 (released as 1.2.0).
    nixpkgs.overlays = [
      (_final: prev: {
        envfs = prev.envfs.overrideAttrs (_oldAttrs: {
          version = "1.2.0";
          src = prev.fetchFromGitHub {
            owner = "Mic92";
            repo = "envfs";
            rev = "1.2.0";
            hash = "sha256-hj/6zS9ebF0IDqgc1Dne59nWx80nk6jn2gj8BzQUFIQ=";
          };
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            src = prev.fetchFromGitHub {
              owner = "Mic92";
              repo = "envfs";
              rev = "1.2.0";
              hash = "sha256-hj/6zS9ebF0IDqgc1Dne59nWx80nk6jn2gj8BzQUFIQ=";
            };
            hash = "sha256-dz3gpE464jnmSDsAsmJHcxUsEKeUURNoUjgGU2214Xg=";
          };
        });
      })
    ];
  };
}
