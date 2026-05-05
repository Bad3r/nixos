_: {
  perSystem = _: {
    treefmt.settings.global.excludes = [
      "inputs/*"
      ".pre-commit-config.yaml"
      "nixos-manual/*"
    ];
  };
}
