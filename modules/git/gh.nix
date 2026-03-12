{
  flake.homeManagerModules.base = _: {
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "https";
        editor = "vim";
      };
    };
  };
}
