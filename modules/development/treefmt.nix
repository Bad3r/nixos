_: {
  perSystem = _: {
    treefmt.settings.global.excludes = [
      "inputs/*"
      ".pre-commit-config.yaml"
      "nixos-manual/*"
      "*.lock"
      "*.patch"
      "package-lock.json"
      "go.mod"
      "go.sum"
      ".gitattributes"
      ".gitignore"
      ".gitmodules"
      ".hgignore"
      ".svnignore"
      "LICENSE"
      "README.md"
      ".actrc"
      ".gitleaks.toml"
      ".sops.yaml"
    ];
  };
}
