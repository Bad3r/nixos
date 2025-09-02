_: {
  nixpkgs.overlays = [
    (_final: prev: {
      firmware-manager = prev.firmware-manager.overrideAttrs (oldAttrs: {
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
          prev.pkg-config
        ];
        buildInputs = (oldAttrs.buildInputs or [ ]) ++ [
          prev.xz # Provides liblzma
        ];
        # Ensure pkg-config can find liblzma
        PKG_CONFIG_PATH = "${prev.xz.dev}/lib/pkgconfig";
      });
    })
  ];
}
