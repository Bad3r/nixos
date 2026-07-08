/*
  Internal: shared Tridactyl configuration
  Description: Declarative rc file consumed by the Tridactyl native messenger
  from $XDG_CONFIG_HOME/tridactyl/tridactylrc.
*/

{ lib }:
let
  upstreamTemplate = {
    source = "https://github.com/tridactyl/tridactyl/blob/master/.tridactylrc";
    note = "The upstream template is almost entirely commented example config; active local commands are generated below.";
  };

  bindings = [
    {
      key = "/";
      command = "fillcmdline find";
    }
    {
      key = "?";
      command = "fillcmdline find --reverse";
    }
    {
      key = "n";
      command = "findnext --search-from-view";
    }
    {
      key = "N";
      command = "findnext --search-from-view --reverse";
    }
    {
      key = "gn";
      command = "findselect";
    }
    {
      key = "gN";
      command = "composite findnext --search-from-view --reverse; findselect";
    }
    {
      key = ",<Space>";
      command = "nohlsearch";
    }
  ];

  renderBinding = binding: "bind ${binding.key} ${binding.command}";

  tridactylrc = ''
    " Source template: ${upstreamTemplate.source}
    " Note: ${upstreamTemplate.note}
    "
    " Vim-style page search using Tridactyl's own find mode.
  ''
  + lib.concatMapStringsSep "\n" renderBinding bindings
  + "\n";
in
{
  configFile."tridactyl/tridactylrc" = {
    text = tridactylrc;
    force = true;
  };
}
