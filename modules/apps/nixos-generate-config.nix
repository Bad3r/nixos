{
  flake.nixosModules.apps."nixos-generate-config" =
    { config, lib, ... }:
    let
      build = config.system.build or { };
      pkg = build."nixos-generate-config" or null;
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
