_:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs."java-lang".extended;
in
{
  options.programs."java-lang".extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Java language support.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      "temurin-bin-25".extended.enable = lib.mkOverride 1050 true;
    };
  };
}
