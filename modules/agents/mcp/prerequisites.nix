_: {
  flake.nixosModules.hosts-common.imports = [
    (
      { config, lib, ... }:
      {
        # The firefox MCP server exists where the camoufox row is on, and its wrapper
        # runs the driver from this app.
        config.programs.geckodriver.extended.enable = lib.mkIf config.programs.camoufox.extended.enable (
          lib.mkOverride 1050 true
        );
      }
    )
  ];
}
