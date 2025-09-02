{
  flake.modules.homeManager.base = _: {
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        editor = "vim";
      };
    };
  };
}
