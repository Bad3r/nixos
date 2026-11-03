/*
  Internal: shared Tridactyl configuration
  Description: Declarative rc file consumed by the Tridactyl native messenger
  from $XDG_CONFIG_HOME/tridactyl/tridactylrc, plus a Stylix palette theme it
  loads from themes/stylix.css.
*/

{ lib, colors }:
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

  # Layered over Tridactyl's built-in auto theme, so only colors are set. The
  # class selector keeps Tridactyl's own pages themed regardless of stylesheet
  # order.
  stylixTheme = with colors; ''
    :root,
    :root.TridactylOwnNamespace {
      --tridactyl-bg: ${base00};
      --tridactyl-fg: ${base05};
      --tridactyl-firefox-2021-redesign-background: ${base00};
      --tridactyl-photon-colours-accent-1: ${base0D};

      --tridactyl-status-bg: ${base01};
      --tridactyl-status-fg: ${base05};
      --tridactyl-status-border: 1px ${base02} solid;

      --tridactyl-search-highlight-color: ${base0A};

      --tridactyl-hintspan-fg: ${base00};
      --tridactyl-hintspan-bg: ${base0D};
      --tridactyl-hintspan-border-color: ${base02};
      --tridactyl-hint-fg: ${base05};
      --tridactyl-hint-bg: ${base01};
      --tridactyl-hint-outline: 1px solid ${base0D};
      --tridactyl-hint-active-fg: ${base00};
      --tridactyl-hint-active-bg: ${base0B};
      --tridactyl-hint-active-outline: 1px solid ${base00};

      --tridactyl-vs-bg: ${base00};
      --tridactyl-vs-fg: ${base05};

      --tridactyl-cmdl-bg: ${base01};
      --tridactyl-cmdl-fg: ${base05};
      --tridactyl-cmplt-bg: ${base00};
      --tridactyl-cmplt-fg: ${base05};
      --tridactyl-cmplt-border-top: 1px solid ${base02};
      --tridactyl-header-first-bg: ${base01};
      --tridactyl-header-second-bg: ${base01};
      --tridactyl-header-third-bg: ${base01};
      --tridactyl-url-fg: ${base0D};
      --tridactyl-url-bg: ${base00};
      --tridactyl-of-fg: ${base05};
      --tridactyl-of-bg: ${base02};

      --tridactyl-highlight-box-bg: ${base01};
      --tridactyl-highlight-box-fg: ${base05};
    }

    /* Hide the thin scrollbar the built-in dark theme draws on Tridactyl's
       own pages; wheel and keyboard scrolling still work. */
    :root.TridactylOwnNamespace {
      scrollbar-width: none;
    }
  '';

  tridactylrc = ''
    " Source template: ${upstreamTemplate.source}
    " Note: ${upstreamTemplate.note}
    "
    " Stylix palette theme from themes/stylix.css.
    colourscheme stylix

    " Vim-style page search using Tridactyl's own find mode.
  ''
  + lib.concatMapStringsSep "\n" renderBinding bindings
  + "\n";
in
{
  configFile = {
    "tridactyl/tridactylrc" = {
      text = tridactylrc;
      force = true;
    };
    "tridactyl/themes/stylix.css" = {
      text = stylixTheme;
      force = true;
    };
  };
}
