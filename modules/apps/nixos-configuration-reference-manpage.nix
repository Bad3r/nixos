{
  flake.nixosModules.apps."nixos-configuration-reference-manpage" =
    { config, lib, ... }:
    let
      manual = config.system.build.manual or null;
      pkg =
        if manual != null && manual ? "nixos-configuration-reference-manpage" then
          manual."nixos-configuration-reference-manpage"
        else
          null;
    in
    lib.mkIf (pkg != null) {
      environment.systemPackages = [ pkg ];
    };
}
