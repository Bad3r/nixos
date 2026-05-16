{
  inputs,
  lib,
  ...
}:
let
  formatterPackages =
    pkgs: with pkgs; [
      nixfmt
      shfmt
      stylua
      ruff
      biome
      (mdformat.withPlugins (ps: [ ps.mdformat-gfm ]))
      taplo
      yamlfmt
    ];
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  flake.lib.formatting.formatterPackages = formatterPackages;

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

      formatter = lib.mkIf (system == "x86_64-linux") config.treefmt.build.wrapper;

      treefmt = {
        projectRootFile = "flake.nix";

        settings.global.excludes = [
          "inputs/**"
          ".pre-commit-config.yaml"
          "nixos-manual/**"
          "secrets/**"
          "*.lock"
          "*.patch"
          "package-lock.json"
          "go.mod"
          "go.sum"
          ".gitattributes"
          ".gitignore"
          ".gitmodules"
          ".hgignore"
          ".svnignore"
          "LICENSE"
          "README.md"
          ".actrc"
          ".gitleaks.toml"
          ".sops.yaml"
        ];

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
            plugins = ps: [ ps.mdformat-gfm ];
            settings = {
              wrap = "keep";
              number = false;
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
