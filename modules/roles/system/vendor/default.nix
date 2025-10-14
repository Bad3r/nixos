_: {
  # Placeholder module anchoring the vendor namespace. Vendor bundles live under
  # modules/roles/system/vendor/<vendor>/default.nix.
  imports = [
    ./system76
  ];
}
