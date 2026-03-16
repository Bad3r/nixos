## TODO

- 1. High: the overlay registration section is stale and host-specific. custom-packages-style-guide.md:262 and custom-packages-style-guide.md:277 still tell authors to register custom packages only in modules/system76/custom-packages-overlay.nix and
     imply that makes them globally available. Current repo practice is per-host overlay wiring, as shown in custom-packages-overlay.nix:19 and custom-packages-overlay.nix:18.
  2. High: the validation command is wrong for overlay-backed custom packages. custom-packages-style-guide.md:292 and custom-packages-style-guide.md:371 recommend nix build .#<name>, but this repo does not expose these packages as top-level flake
     package outputs. I verified that nix develop -c nix build .#sss-pass-gpg-bootstrap fails with “does not provide attribute packages.x86_64-linux.sss-pass-gpg-bootstrap”. The working validation path is via host configs or overlay consumers.
  3. Medium: the app-module guidance under-specifies the host catalog contract. custom-packages-style-guide.md:358 says to skip app modules for host-specific tooling, and custom-packages-style-guide.md:373 stops at “App module created”. In practice,
     host-visible tooling is still modeled as app modules plus explicit host catalog entries, which the push hook enforces. Current evidence: sss-pass-gpg-bootstrap.nix:1, apps-enable.nix:303, apps-enable.nix:280, and the existing host-scoped tooling
     pattern in sss-nix-repair.nix:21.
- burpsuitepro.desktop> /nix/store/a14ldmhl5wsmz4mh9ybbvkvjjbxmkigx-burpsuitepro.desktop/share/applications/burpsuitepro.desktop: hint: value "Development;Security;System" for key "Categories" in group "Desktop Entry" contains more than one main category; application might appear more than once in the application menu
