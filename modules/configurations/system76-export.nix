{
  inputs,
  lib,
  config,
  ...
}:
{
  # Ensure the 'system76' host is exported explicitly to flake outputs.
  # This complements modules/configurations/nixos.nix, which aggregates all hosts.
  # Some environments may elide empty attrsets from flake outputs; this makes
  # the common host available even if aggregation yields an empty set by mistake.
  config.flake =
    lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config)
      {
        nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ config.configurations.nixos.system76.module ];
        };
      };
}
