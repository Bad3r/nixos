_: {
  # Ensure treefmt ignores vendored inputs to keep checks fast and focused
  perSystem =
    { config, ... }:
    {
      treefmt.settings = {
        # Do not format vendored inputs
        global.excludes = [ "inputs/*" ];
        # Generated README must match write-files output exactly; exclude from prettier
        formatter.prettier.excludes = [ "README.md" ];
      };

      files.files = [
        {
          path_ = ".treefmt.toml";
          # Use the config file produced by treefmt-nix from the structured settings
          drv = config.treefmt.build.configFile;
        }
      ];
    };
}
