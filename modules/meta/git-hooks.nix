{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem = _: {
    pre-commit = {
      check.enable = true;
      settings = {
        hooks = {
          nixfmt-rfc-style.enable = true;
          deadnix.enable = true;
          statix.enable = true;
        };
      };
    };
  };
}
