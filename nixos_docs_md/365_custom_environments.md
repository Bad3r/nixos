## Custom environments

There are several extensions for `oh-my-zsh` packaged in `nixpkgs`. One of them is [nix-zsh-completions](https://github.com/spwhitt/nix-zsh-completions) which bundles completion scripts and a plugin for `oh-my-zsh`.

Rather than using a single mutable path for `ZSH_CUSTOM`, it’s also possible to generate this path from a list of Nix packages:

```programlisting
{ pkgs, ... }:
{
  programs.zsh.ohMyZsh.customPkgs = [
    pkgs.nix-zsh-completions
    # and even more...

  ];
}
```

Internally a single store path will be created using `buildEnv`. Please refer to the docs of [`buildEnv`](https://nixos.org/nixpkgs/manual/#sec-building-environment) for further reference.

_Please keep in mind that this is not compatible with `programs.zsh.ohMyZsh.custom` as it requires an immutable store path while `custom` shall remain mutable! An evaluation failure will be thrown if both `custom` and `customPkgs` are set._
