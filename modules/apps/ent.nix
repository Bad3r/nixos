/*
  Package: ent
  Description: Pseudorandom number sequence test program.
  Homepage: https://www.fourmilab.ch/random/
  Documentation: https://www.fourmilab.ch/random/

  Summary:
    * Runs statistical tests (entropy, chi-square, arithmetic mean, Monte Carlo π, serial correlation) on byte or bit streams.
    * Reports compression potential and randomness likelihood for sample data.

  Tests:
    * Entropy: measures information density in bits per character.
    * Chi-square: flags non-random distributions outside the 1-99% confidence range.
    * Arithmetic mean: expected value 127.5 for unbiased byte streams.
    * Monte Carlo π: approximates π using six-byte coordinate sampling.
    * Serial correlation: near zero for random data; approaches 1 for predictable streams.

  Options:
    -b: Treat input as individual bits before computing statistics.
    -c: Print an occurrence table for each byte or bit value.
    -f: Fold uppercase to lowercase using ISO 8859-1 rules before analysis.
    -t: Emit comma-separated output suitable for spreadsheets.
    -u: Show usage information.
*/

{
  flake.nixosModules.apps.ent =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ent ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ent ];
    };
}
