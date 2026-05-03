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
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.jupyter-all = JupyterAllModule;
}
