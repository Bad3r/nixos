_:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.go-lang.extended;
in
{
  options.programs.go-lang.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Go language support.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      go.extended.enable = lib.mkOverride 1050 true;
      gopls.extended.enable = lib.mkOverride 1050 true;
      "golangci-lint".extended.enable = lib.mkOverride 1050 true;
      delve.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
