_:
let
  # A single emulatedSystems entry fans out in the NixOS binfmt module: it
  # registers a QEMU user-mode handler for the system and, because
  # addEmulatedSystemsToNixSandbox defaults true, also appends it to
  # nix.settings.extra-platforms (plus the sandbox interpreter path) so Nix can
  # build those derivations locally under emulation.
  body = {
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
