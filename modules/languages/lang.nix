_: {
  flake.nixosModules.lang = {
    imports = [
      (import ./_lang-python.nix { })
      (import ./_lang-go.nix { })
      (import ./_lang-rust.nix { })
      (import ./_lang-java.nix { })
      (import ./_lang-clojure.nix { })
    ];
  };
}
