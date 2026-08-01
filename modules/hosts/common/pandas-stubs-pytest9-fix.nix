/*
  pandas-stubs is a transitive pytest check-input (openai, pandera, pdfplumber,
  meshtastic, ...). Its test suite sets `filterwarnings = error`, so under
  pytest 9 the collection-time PytestRemovedIn10Warning raised for the
  non-Collection iterable passed to `@pytest.mark.parametrize` in
  tests/arrays/*.py turns into 8 collection errors that abort the build.

  Ignoring only that one warning restores collection (3151 tests pass).
  pythonPackagesExtensions applies to every interpreter set, so the override
  follows the default `python3` interpreter wherever it lands. Drop this once
  nixpkgs adapts pandas-stubs to pytest 9.
*/
_:
let
  body = {
    nixpkgs.overlays = [
      (_final: prev: {
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (_pyfinal: pyprev: {
            pandas-stubs = pyprev.pandas-stubs.overrideAttrs (old: {
              pytestFlags = (old.pytestFlags or [ ]) ++ [
                "-W"
                "ignore::pytest.PytestRemovedIn10Warning"
              ];
            });
          })
        ];
      })
    ];
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
