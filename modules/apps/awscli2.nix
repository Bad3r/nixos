/*
  Package: awscli2
  Description: Amazon Web Services command-line interface v2 for automating AWS APIs.
  Homepage: https://aws.amazon.com/cli/
  Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html
  Repository: https://github.com/aws/aws-cli

  Summary:
    * Provides unified CLI access to manage AWS infrastructure, identities, and services from scripts or terminals.
    * Supports credential profiles, AWS SSO, pagination helpers, and structured JSON/JMESPath output formatting.

  Options:
    --profile <name>: Execute a command using the named credential profile instead of the default.
    --region <code>: Override the default AWS Region for a single invocation.
    --query <JMESPath>: Filter and transform JSON responses with a JMESPath expression.
*/

{
  flake.nixosModules.apps.awscli2 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.awscli2 ];
    };
}
