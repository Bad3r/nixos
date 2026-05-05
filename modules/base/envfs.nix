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
    # Dep lookups (`fetchFromGitHub`, `rustPlatform.fetchCargoVendor`) go
    # through `final` so any other overlay that rebinds them feeds into this
    # build via the fixpoint instead of being silently bypassed (overlay
    # registration order is irrelevant here — the fixpoint observes all
    # overlays). The `prev.envfs.overrideAttrs` entry point stays on `prev`
    # so we extend the unmodified upstream attrs.
    nixpkgs.overlays = [
      (final: prev: {
        envfs = prev.envfs.overrideAttrs (
          _oldAttrs:
          let
            src = final.fetchFromGitHub {
              owner = "Mic92";
              repo = "envfs";
              rev = "1.2.0";
              hash = "sha256-hj/6zS9ebF0IDqgc1Dne59nWx80nk6jn2gj8BzQUFIQ=";
            };
          in
          {
            version = "1.2.0";
            inherit src;
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              hash = "sha256-dz3gpE464jnmSDsAsmJHcxUsEKeUURNoUjgGU2214Xg=";
            };
          }
        );
      })
    ];
  };
}
