# zsh

The owner's interactive zsh is the Home Manager module `flake.homeManagerModules.zsh`, assembled from the files under `modules/shell/zsh/`.
`modules/base/shell-config.nix` keeps the NixOS side: login-shell registration, `/etc/zshrc`, and a completion fallback for accounts without a zshrc of their own.

## Startup order

An interactive shell reads `/etc/zshenv`, `$ZDOTDIR/.zshenv`, `/etc/zshrc`, then `$ZDOTDIR/.zshrc`.
The Home Manager file runs last, so its options, key bindings, and prompt win over the NixOS defaults.
NixOS skips its global `compinit`; the Home Manager zshrc runs the only one, after every `fpath` addition.
Inside `.zshrc`, blocks are ordered with `lib.mkOrder`; the header of `modules/shell/zsh/core.nix` lists the slots Home Manager itself uses.

## Where a change goes

- A shell option, history setting, or shell variable: `modules/shell/zsh/core.nix`.
- A general alias: the matching group in `modules/shell/zsh/aliases.nix`, gated on the app's enable flag when the alias names one tool.
- An alias, variable, or hook for a tool that has a Home Manager app module: that module under `modules/hm-apps/`.
- A function: one file under `modules/shell/zsh/functions/`, named after the function and holding only its body.
- A key binding or zle widget: `modules/shell/zsh/keybindings.nix`.
- A plugin: `modules/shell/zsh/plugins.nix`, sourced from its nixpkgs package.
- A function every account needs in both bash and zsh: a NixOS module under `modules/shell/`.

## Function files

Function files carry no extension and no shebang, because the `shellcheck` hook selects files by shell type and cannot parse zsh.
Home Manager loads them with `autoload -Uz`, so aliases are not expanded inside a function file.
zsh code written inline in a `.nix` file is parsed after the NixOS aliases exist, so it calls `command rm`, `command mv`, and `command mkdir` explicitly.

## Completion cache

`compinit` reuses its dump while the resolved `fpath` is unchanged, which holds until a new generation changes a store path.
A completion directory outside the store needs a manual rebuild:

```sh
command rm ~/.cache/zsh/zcompdump-*
```

## Validation

The `shell/zsh-startup` flake check in `modules/shell/zsh/checks.nix` parses every generated file with `zsh -n`.
It then starts one interactive shell against the generated home and fails on any startup diagnostic.

```sh
nix build --no-link -L 'path:.#checks.x86_64-linux."shell/zsh-startup"'
```

Build the generated `.zshrc` of a host without switching:

```sh
nix build --no-link --print-out-paths \
  'path:.#nixosConfigurations.<host>.config.home-manager.users.<owner>.home.file.".config/zsh/.zshrc".source'
```

Setting `programs.zsh.zprof.enable` in `modules/shell/zsh/core.nix` prints a startup profile in every new shell.
