_: {
  configurations.nixos.songbird.module = {
    # Shared fleet composition lives in modules/hosts/common/imports.nix,
    # including nixos-hardware's common-cpu-intel-cpu-only profile. This is a
    # desktop board (ASUS ROG Maximus Z890 Hero) with no vendor NixOS module,
    # so unlike system76 there is nothing chassis-specific to import; the file
    # carries only host-specific enables.

    # Gaming & performance
    programs = {
      steam.extended.enable = true;
      rip.extended.enable = true;
    };

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
