{
  flake.homeManagerModules.base = _: {
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "https";
        editor = "vim";
        # pager = "bat"; # commented out: gh-cli reads $PAGER
        browser = "xdg-open";
        color_labels = "enabled";
        telemetry = "disabled";

        # toggle all interactive terminal prompts {enabled | disabled}
        # prompt = "enabled";

        # animated spinner shown during API calls and git operations {enabled | disabled}
        spinner = "enabled";

        # when enabled, opens $EDITOR instead of inline prompts for multi-line input such as PR bodies and issue descriptions {enabled | disabled}
        # prefer_editor_prompt = "disabled";

        # path to a Unix domain socket through which to proxy HTTP connections; leave unset to use direct connections
        # http_unix_socket = "";
      };
    };
  };
}
