_:
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs."clojure-lang".extended;
in
{
  options.programs."clojure-lang".extended = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to enable Clojure language support.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs = {
      "clojure-cli".extended.enable = lib.mkOverride 1050 true;
      "clojure-lsp".extended.enable = lib.mkOverride 1050 true;
      leiningen.extended.enable = lib.mkOverride 1050 true;
      babashka.extended.enable = lib.mkOverride 1050 true;
    };
  };
}
