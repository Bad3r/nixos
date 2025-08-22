## Developing the NixOS Test Driver

**Table of Contents**

[Testing changes to the test framework](#sec-test-the-test-framework)

The NixOS test framework is a project of its own.

It consists of roughly the following components:

- `nixos/lib/test-driver`: The Python framework that sets up the test and runs the [`testScript`](#test-opt-testScript)

- `nixos/lib/testing`: The Nix code responsible for the wiring, written using the (NixOS) Module System.

These components are exposed publicly through:

- `nixos/lib/default.nix`: The public interface that exposes the `nixos/lib/testing` entrypoint.

- `flake.nix`: Exposes the `lib.nixos`, including the public test interface.

Beyond the test driver itself, its integration into NixOS and Nixpkgs is important.

- `pkgs/top-level/all-packages.nix`: Defines the `nixosTests` attribute, used by the package `tests` attributes and OfBorg.

- `nixos/release.nix`: Defines the `tests` attribute built by Hydra, independently, but analogous to `nixosTests`

- `nixos/release-combined.nix`: Defines which tests are channel blockers.

Finally, we have legacy entrypoints that users should move away from, but are cared for on a best effort basis. These include `pkgs.nixosTest`, `testing-python.nix` and `make-test-python.nix`.
