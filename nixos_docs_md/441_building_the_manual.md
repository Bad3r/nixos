## Building the Manual

The sources of the [NixOS Manual](index.html "NixOS Manual") are in the [`nixos/doc/manual`](https://github.com/NixOS/nixpkgs/tree/master/nixos/doc/manual) subdirectory of the Nixpkgs repository.

You can quickly validate your edits with `devmode`:

```programlisting
$ cd /path/to/nixpkgs/nixos/doc/manual
$ nix-shell
[nix-shell:~]$ devmode
```

Once you are done making modifications to the manual, it’s important to build it before committing. You can do that as follows:

```programlisting
nix-build nixos/release.nix -A manual.x86_64-linux
```

When this command successfully finishes, it will tell you where the manual got generated. The HTML will be accessible through the `result` symlink at `./result/share/doc/nixos/index.html`.
