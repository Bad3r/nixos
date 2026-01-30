{
  config,
  lib,
  inputs,
  metaOwner,
  ...
}:
let
  selfRevision =
    let
      self = inputs.self or null;
    in
    if self != null then
      let
        dirty = self.dirtyRev or null;
        rev = self.rev or null;
      in
      if dirty != null then dirty else rev
    else
      null;

  # Optional flake module checks
  system76SupportExists = lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config;
  lenovyMonitorExists = lib.hasAttrByPath [ "flake" "nixosModules" "hardware-lenovo-y27q-20" ] config;
in
{
  configurations.nixos.system76.module = {
    # NOTE: All modules/system76/*.nix files are auto-imported by import-tree
    # and contribute to this aggregator via flake-parts. Only actual NixOS
    # modules (exported via flake.nixosModules.* or from external inputs)
    # should be imported here.
    imports = [
      # Required infrastructure (exported NixOS modules)
      # Note: base includes Stylix via modules/style/stylix.nix contribution
      config.flake.nixosModules.base
      config.flake.nixosModules.lang
      config.flake.nixosModules.ssh
      config.flake.nixosModules."duplicati-r2"
      config.flake.nixosModules.mirror-root

      # External hardware modules
      inputs.nixos-hardware.nixosModules.system76
      inputs.nixos-hardware.nixosModules.system76-darp6
    ]
    # Optional modules (graceful degradation)
    ++ lib.optionals system76SupportExists [ config.flake.nixosModules.system76-support ]
    ++ lib.optionals lenovyMonitorExists [ config.flake.nixosModules."hardware-lenovo-y27q-20" ];

    # Pass metaOwner to all imported modules
    _module.args.metaOwner = metaOwner;

    nixpkgs.allowedUnfreePackages = lib.mkAfter [
      "p7zip-rar"
      "rar"
      "unrar"
    ];

    # Hardware support
    hardware.system76.extended.enable = true;

    # Security & authentication
    security.polkit.wheelPowerManagement.enable = true;
    security.polkit.wheelSystemdManagement.enable = true;

    # Gaming & performance
    programs = {
      steam.extended.enable = true;
      rip2.extended.enable = true;
    };

    # Language support
    languages = {
      clojure.extended.enable = true;
      rust.extended.enable = true;
      java.extended.enable = true;
      python.extended.enable = true;
      go.extended.enable = true;
    };
  };

  # Export the System76 configuration so the flake exposes it under nixosConfigurations
  flake = lib.mkIf (lib.hasAttrByPath [ "configurations" "nixos" "system76" "module" ] config) {
    nixosConfigurations.system76 = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          # Dependency Injection via _module.args
          #
          # This propagates metaOwner and inputs to all modules in the configuration tree
          # using flake-parts' _module.args mechanism. Modules receive these as function
          # parameters: { metaOwner, inputs, ... }:
          #
          # Benefits:
          # - Eliminates hardcoded path imports (e.g., import ../../lib/meta-owner-profile.nix)
          # - Enables proper testing and composition
          # - Makes dependencies explicit in function signatures
          # - Provides consistent parameter passing across the module hierarchy
          #
          # See also: modules/meta/owner.nix for the receiving side pattern
          _module.args.metaOwner = metaOwner;
          _module.args.inputs = inputs;
        }
        (
          { lib, ... }:
          lib.mkIf (selfRevision != null) {
            system.configurationRevision = lib.mkDefault selfRevision;
          }
        )
        config.configurations.nixos.system76.module
      ];
      specialArgs = {
        inherit inputs metaOwner;
      };
    };
  };
}
