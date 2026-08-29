_: {
  configurations.nixos.songbird.module = {
    # Shared fleet composition lives in modules/hosts/common/imports.nix,
    # including nixos-hardware's common-cpu-intel-cpu-only profile. This is a
    # desktop board (ASUS ROG Maximus Z890 Hero) with no vendor NixOS module,
    # so unlike system76 there is nothing chassis-specific to import; the file
    # carries only host-specific enables.

    # No programs block: steam and rip are already on in the common baseline,
    # so repeating them here would be a no-op that FR-5 cannot see, since it
    # reads apps-enable.nix's registries and not this file.

    # Language support
    languages = {
      clojure.extended.enable = true;
      rust.extended.enable = true;
      java.extended.enable = true;
      python.extended.enable = true;
      go.extended.enable = true;
    };
  };
}
