/*
  Package: pyyaml
  Description: Next generation YAML parser and emitter for Python.
  Homepage: https://pyyaml.org/
  Documentation: https://pyyaml.org/wiki/PyYAMLDocumentation
  Repository: https://github.com/yaml/pyyaml

  Summary:
    * Full-featured YAML 1.1 parser and emitter with multiple security-tiered loaders (SafeLoader, FullLoader, UnsafeLoader).
    * Optional LibYAML C extension bindings (CLoader/CDumper) for high-performance parsing and serialization.

  Options:
    yaml.safe_load(stream): Parse YAML from a string or file using the safe subset (recommended for untrusted input).
    yaml.safe_dump(data): Serialize Python objects to a YAML string using safe types only.
    yaml.safe_load_all(stream): Parse multiple YAML documents separated by --- markers.
    yaml.safe_dump_all(documents): Serialize a sequence of Python objects as a multi-document YAML stream.
    yaml.add_constructor(tag, constructor): Register a custom tag constructor for extending YAML parsing.
    yaml.add_representer(type, representer): Register a custom type serializer for extending YAML output.
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
