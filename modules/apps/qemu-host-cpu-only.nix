{
  flake.nixosModules.apps."qemu-host-cpu-only" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.qemu_kvm ];
    };
}
