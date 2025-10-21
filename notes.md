1. Decide how to adapt modules/system76/imports.nix to the import-tree layout—either flatten config.flake.nixosModules
   before the lookups (e.g. by running inputs.import-tree.flatten once and caching the result) or teach getModule/
   getRoleModule to read from .content.
2. Once those lookups succeed, re-run the scaffold (nix eval --impure --accept-flake-config … eval.config.debug.hmTrace)
