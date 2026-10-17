# Espanso Matches

Matches extend the defaults through Home Manager's `services.espanso.matches`; enabling espanso and the default triggers are in [Espanso usage](espanso-usage.md).
The match syntax is in the [espanso matches guide](https://espanso.org/docs/matches/basics/).

## Custom Matches

Each attribute is one match file:

```nix
{
  services.espanso.matches = {
    # Add to existing matches
    email = {
      matches = [
        {
          trigger = ":email";
          replace = "your.email@example.com";
        }
        {
          trigger = ":work";
          replace = "work.email@company.com";
        }
      ];
    };

    # Code snippets
    coding = {
      matches = [
        {
          trigger = ":func";
          replace = "function $1() {\n  $0\n}";
        }
        {
          trigger = ":lambda";
          replace = "lambda x: x";
        }
      ];
    };
  };
}
```

## Variables

Espanso supports form input, shell command output, and clipboard content as variables:

```nix
{
  services.espanso.matches.advanced = {
    matches = [
      # Form with user input
      {
        trigger = ":greet";
        replace = "Hello {{name}}!";
        vars = [
          {
            name = "name";
            type = "form";
            params = {
              layout = "Name: [[name]]";
            };
          }
        ];
      }

      # Shell command output
      {
        trigger = ":ip";
        replace = "{{output}}";
        vars = [
          {
            name = "output";
            type = "shell";
            params = {
              cmd = "curl -s ifconfig.me";
            };
          }
        ];
      }

      # Clipboard content
      {
        trigger = ":clip";
        replace = "{{clipboard}}";
        vars = [
          {
            name = "clipboard";
            type = "clipboard";
          }
        ];
      }
    ];
  };
}
```

## Regex Triggers

A regex trigger matches more flexibly and captures named groups:

```nix
{
  services.espanso.matches.regex = {
    matches = [
      {
        regex = ":hi(?P<person>\\w+)";
        replace = "Hello {{person}}!";
      }
      {
        regex = ":math(?P<expr>[0-9+\\-*/]+)";
        replace = "{{result}}";
        vars = [
          {
            name = "result";
            type = "shell";
            params = {
              cmd = "echo \"{{expr}}\" | bc";
            };
          }
        ];
      }
    ];
  };
}
```
