# Module: home/base/git/rebasing.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.homeManager.base
# Pattern: Home Manager base - CLI and terminal environment

{
  flake.modules.homeManager.base = {
    home.packages = [
      # https://github.com/quodlibetor/git-instafix/issues/39
      # pkgs.git-instafix
    ];
    programs.git.extraConfig.rebase.instructionFormat = "%d %s";
  };
}
