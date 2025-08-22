## Configuring Emacs

If you want to only use extension packages from Nixpkgs, you can add `(setq package-archives nil)` to your init file.

After the declarative Emacs package configuration has been tested, previously downloaded packages can be cleaned up by removing `~/.emacs.d/elpa` (do make a backup first, in case you forgot a package).

### A Major Mode for Nix Expressions

Of interest may be `melpaPackages.nix-mode`, which provides syntax highlighting for the Nix language. This is particularly convenient if you regularly edit Nix files.

### Accessing man pages

You can use `woman` to get completion of all available man pages. For example, type `M-x woman <RET> nixos-rebuild <RET>.`
