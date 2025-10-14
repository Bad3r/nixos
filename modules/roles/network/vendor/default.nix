_: {
  # Placeholder module anchoring the vendor namespace. Vendor bundles live under
  # modules/roles/network/vendor/<vendor>/default.nix.
  imports = [
    ./cloudflare
  ];
}
