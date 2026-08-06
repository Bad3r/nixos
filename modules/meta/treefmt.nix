{
  inputs,
  lib,
  ...
}:
let
  mdformatPlugins = ps: [ ps.mdformat-gfm ];

  formatterPackages =
    pkgs: with pkgs; [
      biome
      (mdformat.withPlugins mdformatPlugins)
      nixfmt
      ruff
      shfmt
      stylua
      taplo
      yamlfmt
    ];

  treefmtGlobalExcludes =
    (map (directory: "${directory}/**") [
      "docs/nixos-manual"
      "inputs"
      "secrets"
    ])
    ++ [
      "*.lock"
      "**/*.lock"
      "*.patch"
      "go.mod"
      "go.sum"
      "package-lock.json"
      "LICENSE"
      "README.md"
    ]
    ++ (map (file: ".${file}") [
      "actrc"
      "gitattributes"
      "gitignore"
      "gitmodules"
      "hgignore"
      "pre-commit-config.yaml"
      "sops.yaml"
      "svnignore"
    ]);
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      packages.formatter-toolchain = pkgs.buildEnv {
        name = "formatter-toolchain";
        paths = formatterPackages pkgs ++ [ config.treefmt.build.wrapper ];
        pathsToLink = [ "/bin" ];
      };

      # `formatter.<system>` is reachable only by naming the system, and
      # `nix fmt` hardcodes the `.` installable in lix/nix/fmt.cc, so neither
      # works from a linked worktree without spelling x86_64-linux into every
      # doc. As a package it is `nix run path:.#treefmt -- .` on any system.
      packages.treefmt = config.treefmt.build.wrapper;

      formatter = lib.mkIf (system == "x86_64-linux") config.treefmt.build.wrapper;

      treefmt = {
        projectRootFile = "flake.nix";

        # The managed .gitleaks*.toml names are generated from config.files.file
        # rather than hand-typed here, the same way modules/meta/hooks/gitleaks.nix,
        # modules/meta/hooks/gitleaks-guards.nix and
        # modules/meta/gitleaks-allowlist-scope.nix already derive theirs: a
        # name missing from a hand-typed copy here would be formatted by
        # taplo, so write-files and the formatter would disagree and
        # managed-files-drift would report churn on a file nobody edited.
        settings.global.excludes =
          treefmtGlobalExcludes
          ++ lib.filter (n: lib.hasPrefix ".gitleaks" n && lib.hasSuffix ".toml" n) (
            lib.attrNames config.files.file
          );

        programs = {
          nixfmt.enable = true;
          shfmt.enable = true;
          ruff-format.enable = true;

          stylua = {
            enable = true;
            settings = {
              indent_type = "Spaces";
              indent_width = 2;
              column_width = 120;
            };
          };

          biome = {
            enable = true;
            formatCommand = "format";
            includes = [
              "*.js"
              "*.jsx"
              "*.ts"
              "*.tsx"
              "*.mjs"
              "*.mts"
              "*.cjs"
              "*.cts"
              "*.json"
              "*.jsonc"
              "*.css"
              "*.html"
            ];
            # treefmt-nix maps Biome 2.4 to an older schema that lacks HTML settings.
            validate.enable = false;
            settings = {
              formatter.enabled = true;
              javascript.formatter.enabled = true;
              json.formatter.enabled = true;
              css.formatter.enabled = true;
              html.formatter.enabled = true;
            };
          };

          mdformat = {
            enable = true;
            includes = [
              "*.md"
              "*.markdown"
            ];
            plugins = mdformatPlugins;
            settings = {
              wrap = "keep";
              number = true;
              end-of-line = "lf";
            };
          };

          taplo = {
            enable = true;
            settings.formatting = {
              reorder_keys = false;
              column_width = 120;
              indent_string = "  ";
            };
          };

          yamlfmt = {
            enable = true;
            excludes = [
              ".github/workflows/**"
              ".github/ISSUE_TEMPLATE/**"
            ];
            settings = {
              line_ending = "lf";
              gitignore_excludes = true;
              formatter = {
                type = "basic";
                retain_line_breaks = true;
                trim_trailing_whitespace = true;
                eof_newline = true;
              };
            };
          };
        };
      };
    };
}
