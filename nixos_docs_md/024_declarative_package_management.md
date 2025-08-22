## Declarative Package Management

With declarative package management, you specify which packages you want on your system by setting the option [`environment.systemPackages`](options.html#opt-environment.systemPackages). For instance, adding the following line to `configuration.nix` enables the Mozilla Thunderbird email application:

```programlisting
{ environment.systemPackages = [ pkgs.thunderbird ]; }
```

The effect of this specification is that the Thunderbird package from Nixpkgs will be built or downloaded as part of the system when you run `nixos-rebuild switch`.

### Note

Some packages require additional global configuration such as D-Bus or systemd service registration so adding them to [`environment.systemPackages`](options.html#opt-environment.systemPackages) might not be sufficient. You are advised to check the [list of options](options.html "Appendix A. Configuration Options") whether a NixOS module for the package does not exist.

You can get a list of the available packages as follows:

```programlisting
$ nix-env -qaP '*' --description
nixos.firefox   firefox-23.0   Mozilla Firefox - the browser, reloaded
...
```

The first column in the output is the _attribute name_, such as `nixos.thunderbird`.

Note: the `nixos` prefix tells us that we want to get the package from the `nixos` channel and works only in CLI tools. In declarative configuration use `pkgs` prefix (variable).

To “uninstall” a package, remove it from [`environment.systemPackages`](options.html#opt-environment.systemPackages) and run `nixos-rebuild switch`.

### Customising Packages

The Nixpkgs configuration for a NixOS system is set by the `nixpkgs.config` option.

**Example 6. Globally allow unfree packages**

```programlisting
{
  nixpkgs.config = {
    allowUnfree = true;
  };
}
```

### Note

This only allows unfree software in the given NixOS configuration. For users invoking Nix commands such as [`nix-build`](https://nixos.org/manual/nix/stable/command-ref/nix-build), Nixpkgs is configured independently. See the [Nixpkgs manual section on global configuration](https://nixos.org/manual/nixpkgs/unstable/#chap-packageconfig) for details.

Some packages in Nixpkgs have options to enable or disable optional functionality, or change other aspects of the package.

### Warning

Unfortunately, Nixpkgs currently lacks a way to query available package configuration options.

### Note

For example, many packages come with extensions one might add. Examples include:

- [`passExtensions.pass-otp`](https://search.nixos.org/packages?query=passExtensions.pass-otp)

- [`python312Packages.requests`](https://search.nixos.org/packages?query=python312Packages.requests)

You can use them like this:

```programlisting
{
  environment.systemPackages = with pkgs; [
    sl
    (pass.withExtensions (
      subpkgs: with subpkgs; [
        pass-audit
        pass-otp
        pass-genphrase
      ]
    ))
    (python3.withPackages (subpkgs: with subpkgs; [ requests ]))
    cowsay
  ];
}
```

Apart from high-level options, it’s possible to tweak a package in almost arbitrary ways, such as changing or disabling dependencies of a package. For instance, the Emacs package in Nixpkgs by default has a dependency on GTK 2. If you want to build it against GTK 3, you can specify that as follows:

```programlisting
{ environment.systemPackages = [ (pkgs.emacs.override { gtk = pkgs.gtk3; }) ]; }
```

The function `override` performs the call to the Nix function that produces Emacs, with the original arguments amended by the set of arguments specified by you. So here the function argument `gtk` gets the value `pkgs.gtk3`, causing Emacs to depend on GTK 3. (The parentheses are necessary because in Nix, function application binds more weakly than list construction, so without them, [`environment.systemPackages`](options.html#opt-environment.systemPackages) would be a list with two elements.)

Even greater customisation is possible using the function `overrideAttrs`. While the `override` mechanism above overrides the arguments of a package function, `overrideAttrs` allows changing the _attributes_ passed to `mkDerivation`. This permits changing any aspect of the package, such as the source code. For instance, if you want to override the source code of Emacs, you can say:

```programlisting
{
  environment.systemPackages = [
    (pkgs.emacs.overrideAttrs (oldAttrs: {
      name = "emacs-25.0-pre";
      src = /path/to/my/emacs/tree;
    }))
  ];
}
```

Here, `overrideAttrs` takes the Nix derivation specified by `pkgs.emacs` and produces a new derivation in which the original’s `name` and `src` attribute have been replaced by the given values by re-calling `stdenv.mkDerivation`. The original attributes are accessible via the function argument, which is conventionally named `oldAttrs`.

The overrides shown above are not global. They do not affect the original package; other packages in Nixpkgs continue to depend on the original rather than the customised package. This means that if another package in your system depends on the original package, you end up with two instances of the package. If you want to have everything depend on your customised instance, you can apply a _global_ override as follows:

```programlisting
{
  nixpkgs.config.packageOverrides = pkgs: {
    emacs = pkgs.emacs.override { gtk = pkgs.gtk3; };
  };
}
```

The effect of this definition is essentially equivalent to modifying the `emacs` attribute in the Nixpkgs source tree. Any package in Nixpkgs that depends on `emacs` will be passed your customised instance. (However, the value `pkgs.emacs` in `nixpkgs.config.packageOverrides` refers to the original rather than overridden instance, to prevent an infinite recursion.)

### Adding Custom Packages

It’s possible that a package you need is not available in NixOS. In that case, you can do two things. Either you can package it with Nix, or you can try to use prebuilt packages from upstream. Due to the peculiarities of NixOS, it is important to note that building software from source is often easier than using pre-built executables.

#### Building with Nix

This can be done either in-tree or out-of-tree. For an in-tree build, you can clone the Nixpkgs repository, add the package to your clone, and (optionally) submit a patch or pull request to have it accepted into the main Nixpkgs repository. This is described in detail in the [Nixpkgs manual](https://nixos.org/nixpkgs/manual). In short, you clone Nixpkgs:

```programlisting
$ git clone https://github.com/NixOS/nixpkgs
$ cd nixpkgs
```

Then you write and test the package as described in the Nixpkgs manual. Finally, you add it to [`environment.systemPackages`](options.html#opt-environment.systemPackages), e.g.

```programlisting
{ environment.systemPackages = [ pkgs.my-package ]; }
```

and you run `nixos-rebuild`, specifying your own Nixpkgs tree:

```programlisting

# nixos-rebuild switch -I nixpkgs=/path/to/my/nixpkgs

```

The second possibility is to add the package outside of the Nixpkgs tree. For instance, here is how you specify a build of the [GNU Hello](https://www.gnu.org/software/hello/) package directly in `configuration.nix`:

```programlisting
{
  environment.systemPackages =
    let
      my-hello =
        with pkgs;
        stdenv.mkDerivation rec {
          name = "hello-2.8";
          src = fetchurl {
            url = "mirror://gnu/hello/${name}.tar.gz";
            hash = "sha256-5rd/gffPfa761Kn1tl3myunD8TuM+66oy1O7XqVGDXM=";
          };
        };
    in
    [ my-hello ];
}
```

Of course, you can also move the definition of `my-hello` into a separate Nix expression, e.g.

```programlisting
{ environment.systemPackages = [ (import ./my-hello.nix) ]; }
```

where `my-hello.nix` contains:

```programlisting
with import <nixpkgs> { }; # bring all of Nixpkgs into scope

stdenv.mkDerivation rec {
  name = "hello-2.8";
  src = fetchurl {
    url = "mirror://gnu/hello/${name}.tar.gz";
    hash = "sha256-5rd/gffPfa761Kn1tl3myunD8TuM+66oy1O7XqVGDXM=";
  };
}
```

This allows testing the package easily:

```programlisting
$ nix-build my-hello.nix
$ ./result/bin/hello
Hello, world!
```

#### Using pre-built executables

Most pre-built executables will not work on NixOS. There are two notable exceptions: flatpaks and AppImages. For flatpaks see the [dedicated section](#module-services-flatpak "Flatpak"). AppImages can run “as-is” on NixOS.

First you need to enable AppImage support: add to `/etc/nixos/configuration.nix`

```programlisting
{
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;
}
```

Then you can run the AppImage “as-is” or with `appimage-run foo.appimage`.

If there are shared libraries missing add them with

```programlisting
{
  programs.appimage.package = pkgs.appimage-run.override {
    extraPkgs = pkgs: [
      # missing libraries here, e.g.: `pkgs.libepoxy`

    ];
  };
}
```

To make other pre-built executables work on NixOS, you need to package them with Nix and special helpers like `autoPatchelfHook` or `buildFHSEnv`. See the [Nixpkgs manual](https://nixos.org/nixpkgs/manual) for details. This is complex and often doing a source build is easier.
