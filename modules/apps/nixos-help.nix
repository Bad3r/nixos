{
  flake.nixosModules.apps."nixos-help" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      manual = config.system.build.manual or { };
      pkg = manual."nixos-help" or (pkgs."nixos-help" or null);
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
