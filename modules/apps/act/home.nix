_: {
  flake.homeManagerModules.apps.act =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "act" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        xdg.configFile."act/actrc".text = ''
          -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest
          -P ubuntu-24.04=ghcr.io/catthehacker/ubuntu:act-24.04
          -P ubuntu-22.04=ghcr.io/catthehacker/ubuntu:act-22.04
          -P ubuntu-20.04=ghcr.io/catthehacker/ubuntu:act-20.04
          -P ubuntu-18.04=ghcr.io/catthehacker/ubuntu:act-18.04

          # Named volume keeps /nix across runs; act splits a line once, so -v shares the value.
          --container-options -v nix-store:/nix
          --container-daemon-socket -
        '';
      };
    };
}
