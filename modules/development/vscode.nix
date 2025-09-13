{
  nixpkgs.allowedUnfreePackages = [
    "code"
    "vscode"
    "vscode-fhs"
  ];

  # Gate installing VS Code (FHS) via a dedicated role module instead of the
  # base workstation profile. See roles/dev-fhs.nix.
  flake.nixosModules.workstation = _: { };
}
