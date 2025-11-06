_:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs."python-lang".extended;
in
{
  options.programs."python-lang".extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Python language support.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      python.extended.enable = lib.mkOverride 1050 true;
      uv.extended.enable = lib.mkOverride 1050 true;
      pyright.extended.enable = lib.mkOverride 1050 true;
      ruff.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
