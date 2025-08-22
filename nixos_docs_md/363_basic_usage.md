## Basic usage

The module uses the `oh-my-zsh` package with all available features. The initial setup using Nix expressions is fairly similar to the configuration format of `oh-my-zsh`.

```programlisting
{
  programs.zsh.ohMyZsh = {
    enable = true;
    plugins = [
      "git"
      "python"
      "man"
    ];
    theme = "agnoster";
  };
}
```

For a detailed explanation of these arguments please refer to the [`oh-my-zsh` docs](https://github.com/robbyrussell/oh-my-zsh/wiki).

The expression generates the needed configuration and writes it into your `/etc/zshrc`.
