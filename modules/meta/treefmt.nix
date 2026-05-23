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
      "inputs"
      "nixos-manual"
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
      "gitleaks.toml"
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

      formatter = lib.mkIf (system == "x86_64-linux") config.treefmt.build.wrapper;

      treefmt = {
        projectRootFile = "flake.nix";

        settings.global.excludes = treefmtGlobalExcludes;

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
