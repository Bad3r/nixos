## 2025-09-09

- fix(media): mpv HM module now uses `xdg.configFile` and removes unused param; flake checks pass.
- feat(office): added `modules/office/planify.nix` to include `pkgs.planify` in `pc` systemPackages.
 - refactor(flake): moved `flake.meta` → `flake.lib.meta`, introduced `flake.nixosModules`/`flake.homeManagerModules`, and set flake-parts `systems = ["x86_64-linux"]` to address unknown output and incompatible systems warnings.
