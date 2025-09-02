## Installing Emacs

Emacs can be installed in the normal way for Nix (see [_Package Management_](#sec-package-management "Package Management")). In addition, a NixOS _service_ can be enabled.

### The Different Releases of Emacs

Nixpkgs defines several basic Emacs packages. The following are attributes belonging to the `pkgs` set:

`emacs`
The latest stable version of Emacs using the [GTK 2](http://www.gtk.org) widget toolkit.

`emacs-nox`
Emacs built without any dependency on X11 libraries.

`emacsMacport`
Emacs with the “Mac port” patches, providing a more native look and feel under macOS.

If those aren’t suitable, then the following imitation Emacs editors are also available in Nixpkgs: [Zile](https://www.gnu.org/software/zile/), [mg](http://homepage.boetes.org/software/mg/), [Yi](http://yi-editor.github.io/), [jmacs](https://joe-editor.sourceforge.io/).

### Adding Packages to Emacs

Emacs includes an entire ecosystem of functionality beyond text editing, including a project planner, mail and news reader, debugger interface, calendar, and more.

Most extensions are gotten with the Emacs packaging system (`package.el`) from [Emacs Lisp Package Archive (ELPA)](https://elpa.gnu.org/), [MELPA](https://melpa.org/), [MELPA Stable](https://stable.melpa.org/), and [Org ELPA](http://orgmode.org/elpa.html). Nixpkgs is regularly updated to mirror all these archives.

Under NixOS, you can continue to use `package-list-packages` and `package-install` to install packages. You can also declare the set of Emacs packages you need using the derivations from Nixpkgs. The rest of this section discusses declarative installation of Emacs packages through nixpkgs.

The first step to declare the list of packages you want in your Emacs installation is to create a dedicated derivation. This can be done in a dedicated `emacs.nix` file such as:

**Example 7. Nix expression to build Emacs with packages (`emacs.nix`)**

```programlisting
/*
  This is a nix expression to build Emacs and some Emacs packages I like
  from source on any distribution where Nix is installed. This will install
  all the dependencies from the nixpkgs repository and build the binary files
  without interfering with the host distribution.

  To build the project, type the following from the current directory:

  $ nix-build emacs.nix

  To run the newly compiled executable:

  $ ./result/bin/emacs
*/

# The first non-comment line in this file indicates that

# the whole file represents a function.,
}:

let
  # The let expression below defines a myEmacs binding pointing to the

  # current stable version of Emacs. This binding is here to separate

  # the choice of the Emacs binary from the specification of the

  # required packages.

  myEmacs = pkgs.emacs;
  # This generates an emacsWithPackages function. It takes a single

  # argument: a function from a package set to a list of packages

  # (the packages that will be available in Emacs).

  emacsWithPackages = (pkgs.emacsPackagesFor myEmacs).emacsWithPackages;
  # The rest of the file specifies the list of packages to install. In the

  # example, two packages (magit and zerodark-theme) are taken from

  # MELPA stable.

in
emacsWithPackages (
  epkgs:
  (with epkgs.melpaStablePackages; [
    magit # ; Integrate git <C-x g>

    zerodark-theme # ; Nicolas' theme

  ])
  # Two packages (undo-tree and zoom-frm) are taken from MELPA.

  ++ (with epkgs.melpaPackages; [
    undo-tree # ; <C-x u> to show the undo tree

    zoom-frm # ; increase/decrease font size for all buffers %lt;C-x C-+>

  ])
  # Three packages are taken from GNU ELPA.

  ++ (with epkgs.elpaPackages; [
    auctex # ; LaTeX mode

    beacon # ; highlight my cursor when scrolling

    nameless # ; hide current package name everywhere in elisp code

  ])
  # notmuch is taken from a nixpkgs derivation which contains an Emacs mode.

  ++ [
    pkgs.notmuch # From main packages set

  ]
)
```

The result of this configuration will be an **emacs** command which launches Emacs with all of your chosen packages in the `load-path`.

You can check that it works by executing this in a terminal:

```programlisting
$ nix-build emacs.nix
$ ./result/bin/emacs -q
```

and then typing `M-x package-initialize`. Check that you can use all the packages you want in this Emacs instance. For example, try switching to the zerodark theme through `M-x load-theme <RET> zerodark <RET> y`.

### Tip

A few popular extensions worth checking out are: auctex, company, edit-server, flycheck, helm, iedit, magit, multiple-cursors, projectile, and yasnippet.

The list of available packages in the various ELPA repositories can be seen with the following commands:

**Example 8. Querying Emacs packages**

```programlisting
nix-env -f "<nixpkgs>" -qaP -A emacs.pkgs.elpaPackages
nix-env -f "<nixpkgs>" -qaP -A emacs.pkgs.melpaPackages
nix-env -f "<nixpkgs>" -qaP -A emacs.pkgs.melpaStablePackages
nix-env -f "<nixpkgs>" -qaP -A emacs.pkgs.orgPackages
```

If you are on NixOS, you can install this particular Emacs for all users by putting the `emacs.nix` file in `/etc/nixos` and adding it to the list of system packages (see [the section called “Declarative Package Management”](#sec-declarative-package-mgmt "Declarative Package Management")). Simply modify your file `configuration.nix` to make it contain:

**Example 9. Custom Emacs in `configuration.nix`**

```programlisting
{
  environment.systemPackages = [
    # [...]

    (import ./emacs.nix { inherit pkgs; })
  ];
}
```

In this case, the next **nixos-rebuild switch** will take care of adding your **emacs** to the `PATH` environment variable (see [_Changing the Configuration_](#sec-changing-config "Changing the Configuration")).

If you are not on NixOS or want to install this particular Emacs only for yourself, you can do so by putting `emacs.nix` in `~/.config/nixpkgs` and adding it to your `~/.config/nixpkgs/config.nix` (see [Nixpkgs manual](https://nixos.org/nixpkgs/manual/#sec-modify-via-packageOverrides)):

**Example 10. Custom Emacs in `~/.config/nixpkgs/config.nix`**

```programlisting
{
  packageOverrides =
    super:
    let
      self = super.pkgs;
    in
    {
      myemacs = import ./emacs.nix { pkgs = self; };
    };
}
```

In this case, the next `nix-env -f '<nixpkgs>' -iA myemacs` will take care of adding your emacs to the `PATH` environment variable.

### Advanced Emacs Configuration

If you want, you can tweak the Emacs package itself from your `emacs.nix`. For example, if you want to have a GTK 3-based Emacs instead of the default GTK 2-based binary and remove the automatically generated `emacs.desktop` (useful if you only use **emacsclient**), you can change your file `emacs.nix` in this way:

**Example 11. Custom Emacs build**

```programlisting
{
  pkgs ? import <nixpkgs> { },
}:
let
  myEmacs =
    (pkgs.emacs.override {
      # Use gtk3 instead of the default gtk2

      withGTK3 = true;
      withGTK2 = false;
    }).overrideAttrs
      (attrs: {
        # I don't want emacs.desktop file because I only use

        # emacsclient.

        postInstall = (attrs.postInstall or "") + ''
          rm $out/share/applications/emacs.desktop
        '';
      });
in
[
  # ...

]
```

After building this file as shown in [Example 7](#ex-emacsNix "Example 7. Nix expression to build Emacs with packages (emacs.nix)"), you will get an GTK 3-based Emacs binary pre-loaded with your favorite packages.
