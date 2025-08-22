## Network Problems

Nix uses a so-called _binary cache_ to optimise building a package from source into downloading it as a pre-built binary. That is, whenever a command like `nixos-rebuild` needs a path in the Nix store, Nix will try to download that path from the Internet rather than build it from source. The default binary cache is `https://cache.nixos.org/`. If this cache is unreachable, Nix operations may take a long time due to HTTP connection timeouts. You can disable the use of the binary cache by adding `--option use-binary-caches false`, e.g.

```programlisting

# nixos-rebuild switch --option use-binary-caches false

```

If you have an alternative binary cache at your disposal, you can use it instead:

```programlisting

# nixos-rebuild switch --option binary-caches http://my-cache.example.org/

```

# Development

This chapter describes how you can modify and extend NixOS.

**Table of Contents**

[Getting the Sources](#sec-getting-sources)

[Writing NixOS Modules](#sec-writing-modules)

[Building Specific Parts of NixOS](#sec-building-parts)

[Bootspec](#sec-bootspec)

[What happens during a system switch?](#sec-switching-systems)

[Writing NixOS Documentation](#sec-writing-documentation)

[NixOS Tests](#sec-nixos-tests)

[Developing the NixOS Test Driver](#chap-developing-the-test-driver)

[Testing the Installer](#ch-testing-installer)

[Modular Services](#modular-services)
