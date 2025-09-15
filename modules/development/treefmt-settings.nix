_: {
  # Ensure treefmt ignores vendored inputs to keep checks fast and focused
  perSystem = _: {
    treefmt.settings.global.excludes = [ "inputs/*" ];
  };
}
