# modules/owner.nix

{ config, ... }:
{
  flake = {
    meta.owner = {
      email = "Bad3r <@> Unsigned.sh";
      name = "Bad3r";
      username = "bad3r";
      matrix = "@<Bad3r>:matrix.org"; # TODO: Verify
    };

    modules = {
      nixos.pc = {
        users.users.${config.flake.meta.owner.username} = {
          isNormalUser = true;
          initialPassword = "";
          extraGroups = [
            "networkmanager"
            "video"
            "render"
          ];
        };

        nix.settings.trusted-users = [ config.flake.meta.owner.username ];
      };
    };
  };
}
