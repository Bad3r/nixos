## Package your own customizations

If third-party customizations (e.g. new themes) are supposed to be added to `oh-my-zsh` there are several pitfalls to keep in mind:

- To comply with the default structure of `ZSH` the entire output needs to be written to `$out/share/zsh.`

- Completion scripts are supposed to be stored at `$out/share/zsh/site-functions`. This directory is part of the [`fpath`](https://zsh.sourceforge.io/Doc/Release/Functions.html) and the package should be compatible with pure `ZSH` setups. The module will automatically link the contents of `site-functions` to completions directory in the proper store path.

- The `plugins` directory needs the structure `pluginname/pluginname.plugin.zsh` as structured in the [upstream repo.](https://github.com/robbyrussell/oh-my-zsh/tree/91b771914bc7c43dd7c7a43b586c5de2c225ceb7/plugins)

A derivation for `oh-my-zsh` may look like this:

```programlisting
{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  name = "exemplary-zsh-customization-${version}";
  version = "1.0.0";
  src = fetchFromGitHub {
    # path to the upstream repository

  };

  dontBuild = true;
  installPhase = ''
    mkdir -p $out/share/zsh/site-functions
    cp {themes,plugins} $out/share/zsh
    cp completions $out/share/zsh/site-functions
  '';
}
```
