{ metaOwner, ... }:
{
  configurations.nixos.songbird.module = {
    home-manager.users.${metaOwner.username}.programs.git.maintenance = {
      enable = true;
      # A listed path that is not a repository fails every timer run.
      repositories = [ "/data/Projects/igit/fork-nixpkgs" ];
    };
  };
}
