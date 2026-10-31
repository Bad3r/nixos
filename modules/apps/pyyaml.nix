/*
  Package: pyyaml
  Description: Next generation YAML parser and emitter for Python.
  Homepage: https://pyyaml.org/
  Documentation: https://pyyaml.org/wiki/PyYAMLDocumentation
  Repository: https://github.com/yaml/pyyaml

  Summary:
    * Full-featured YAML 1.1 parser and emitter with multiple security-tiered loaders (SafeLoader, FullLoader, UnsafeLoader).
    * Optional LibYAML C extension bindings (CLoader/CDumper) for high-performance parsing and serialization.
*/
_:
let
  PyYamlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pyyaml.extended;
    in
    {
      options.programs.pyyaml.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pyyaml.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "pyyaml" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.pyyaml = PyYamlModule;
}
