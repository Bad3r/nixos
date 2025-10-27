_:
let
  owner = import ../../lib/meta-owner-profile.nix;
in
{
  flake = {
    lib.meta.owner = owner;

    nixosModules = {
      base = {
        users.users.${owner.username} = {
          isSystemUser = true;
          uid = 1000;
          group = "users";
          createHome = true;
          home = "/home/${owner.username}";
          useDefaultShell = true;
          initialPassword = "";

          extraGroups = [
            "wheel"
            "networkmanager"
          ];
        };

        nix.settings.trusted-users = [ owner.username ];
      };
    };
  };
}
