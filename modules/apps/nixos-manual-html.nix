{
  flake.nixosModules.apps."nixos-manual-html" =
    { config, lib, ... }:
    let
      manual = config.system.build.manual or null;
      pkg = if manual != null && manual ? manualHTML then manual.manualHTML else null;
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
