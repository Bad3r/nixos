/*
  Package: bc
  Description: Arbitrary-precision calculator language for interactive and scripted math.
  Homepage: https://www.gnu.org/software/bc/
  Documentation: https://www.gnu.org/software/bc/manual/
  Repository: https://git.savannah.gnu.org/cgit/bc.git

  Summary:
    * Evaluates expressions with unlimited precision, user-defined functions, and control structures.
    * Runs in interactive REPL or batch mode, making it suitable for pipelines and automation.

  Options:
    -l: Load the standard math library with sine, cosine, and exponential functions.
    -q: Suppress the startup banner when entering interactive mode.
    -f <file>: Execute statements from the specified script file.
*/

{
  flake.nixosModules.apps.bc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.bc ];
    };
}
