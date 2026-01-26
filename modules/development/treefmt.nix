_: {
  # Ensure treefmt ignores vendored inputs to keep checks fast and focused
  perSystem = _: {
    treefmt.settings = {
      # Do not format vendored inputs or generated config files
      global.excludes = [
        "inputs/*"
        "lefthook.yml"
        "nixos-manual/*"
      ];
      # Generated README must match write-files output exactly; exclude from prettier
      formatter.prettier.excludes = [ "README.md" ];
    };
  };
}
