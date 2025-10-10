_: {
  # Ensure treefmt ignores vendored inputs to keep checks fast and focused
  perSystem =
    { config, lib, ... }:
    {
      treefmt.settings = {
        global.excludes = lib.mkForce [
          "*.lock"
          "*.patch"
          "package-lock.json"
          "go.mod"
          "go.sum"
          ".gitignore"
          ".gitmodules"
          ".hgignore"
          ".svnignore"
          "inputs/*"
          "secrets/**"
        ];
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
