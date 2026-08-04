/*
  Package: jupyter-all
  Description: Jupyter wrapper bundling JupyterLab, the classic notebook server, and a curated set of language kernels.
  Homepage: https://jupyter.org/
  Documentation: https://docs.jupyter.org/
  Repository: https://github.com/jupyter/notebook

  Summary:
    * Provides a single environment with `jupyter`, `jupyter-lab`, `jupyter-notebook`, `jupyter-console`, `jupyter-nbconvert`, and `ipython` entry points.
    * Ships additional Clojure (Clojupyter) and Octave kernels in addition to the default Python kernel via the nixpkgs override.

  Options:
    notebook: Launch the classic web-based Jupyter Notebook server.
    lab: Start the JupyterLab next-generation notebook IDE.
    console: Open a terminal-based interactive kernel session.
    nbconvert <input>: Convert notebooks to HTML, PDF, slides, Markdown, scripts, or other formats.
    kernelspec <subcommand>: Manage installed Jupyter kernels (list, install, remove, provision).
    server: Run only the headless Jupyter server backend without a UI.

  Notes:
    * `jupyter-all` is `jupyter.override` from nixpkgs that registers Clojure (clojupyter) and Octave kernels alongside the Python kernel.
    * The Wolfram kernel is intentionally excluded upstream because it is unfree.
    * Kernelspecs are re-exported on JUPYTER_PATH so external clients such as the VS Code Jupyter extension can launch them.
*/
_:
let
  JupyterAllModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."jupyter-all".extended;

      # jupyter-all replaces the jupyter-kernel definition set instead of
      # extending it, so upstream drops jupyter-kernel.default.python3 and its
      # absolute interpreter argv. The only surviving Python kernelspec is
      # ipykernel's own, whose argv[0] is the bare string "python". That
      # resolves through PATH, and outside the wrapped `jupyter` binary PATH
      # yields programs.python.extended's hiPrio python313, which has no
      # ipykernel.
      kernelspecs =
        pkgs.runCommand "jupyter-all-kernelspecs"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            ${cfg.package}/bin/python -c 'import ipykernel_launcher'

            install -d "$out/share/jupyter/kernels/python3"
            install -m444 -t "$out/share/jupyter/kernels/python3" \
              ${cfg.package}/share/jupyter/kernels/python3/logo-*
            jq --arg interpreter '${cfg.package}/bin/python' '.argv[0] = $interpreter' \
              ${cfg.package}/share/jupyter/kernels/python3/kernel.json \
              > "$out/share/jupyter/kernels/python3/kernel.json"
          '';
    in
    {
      options.programs."jupyter-all".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable jupyter-all.";
        };

        package = lib.mkPackageOption pkgs "jupyter-all" { };
      };

      config = lib.mkIf cfg.enable {
        environment = {
          # hiPrio so the absolute-argv kernel.json wins the system-path
          # collision against the copy bundled in cfg.package.
          systemPackages = [
            cfg.package
            (lib.hiPrio kernelspecs)
          ];

          # NixOS links no /share/jupyter by default, so kernelspecs stay
          # reachable only through the wrapped `jupyter` binary, which sets
          # JUPYTER_PATH itself. Exported through sessionVariables
          # (PAM-initialised) rather than variables (shell-profile only) so
          # editors started from the desktop inherit it.
          pathsToLink = [ "/share/jupyter" ];
          sessionVariables.JUPYTER_PATH = "/run/current-system/sw/share/jupyter";
        };
      };
    };
in
{
  flake.nixosModules.apps.jupyter-all = JupyterAllModule;
}
