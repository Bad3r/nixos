{
  flake.nixosModules.apps."nixos-version" =
    { config, lib, ... }:
    let
      build = config.system.build or { };
      pkg = build."nixos-version" or null;
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
