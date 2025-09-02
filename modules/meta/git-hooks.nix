{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem = _: {
    pre-commit = {
      check.enable = true;
      settings = {
        hooks = {
          # Nix-specific hooks
          nixfmt-rfc-style.enable = true;
          deadnix.enable = true;
          statix.enable = true;
          flake-checker.enable = true;

          # Shell script quality
          shellcheck.enable = true;

          # Documentation and text quality
          typos.enable = true;
          trim-trailing-whitespace.enable = true;

          # Security
          detect-private-keys.enable = true;
          ripsecrets = {
            enable = true;
            excludes = [
              "nixos_docs_md/.*\\.md$" # Documentation files with examples
              "modules/networking/networking.nix" # Contains public minisign key
            ];
          };

          # Config file validation
          check-yaml.enable = true;
          check-json.enable = true;
        };
      };
    };
  };
}
