_: {
  # Generate a .treefmt.toml from current treefmt-nix settings so
  # the plain `treefmt` command can be used outside the devshell.
  perSystem =
    { config, ... }:
    {
      files.files = [
        {
          path_ = ".treefmt.toml";
          # Use the config file produced by treefmt-nix from the structured settings
          drv = config.treefmt.build.configFile;
        }
      ];
    };
}
