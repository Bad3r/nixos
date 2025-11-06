_:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.rust-lang.extended;
in
{
  options.programs.rust-lang.extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Rust language support.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      rustc.extended.enable = lib.mkOverride 1050 true;
      cargo.extended.enable = lib.mkOverride 1050 true;
      "rust-analyzer".extended.enable = lib.mkOverride 1050 true;
      "rust-clippy".extended.enable = lib.mkOverride 1050 true;
      rustfmt.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
