## Hooks

Cert Spotter supports running custom hooks instead of (or in addition to) sending emails. Hooks are shell scripts that will be passed certain environment variables.

To see hook documentation, see Cert Spotter’s man pages:

```programlisting
nix-shell -p certspotter --run 'man 8 certspotter-script'
```

For example, you can remove `emailRecipients` and send email notifications manually using the following hook:

```programlisting
{
  services.certspotter.hooks = [
    (pkgs.writeShellScript "certspotter-hook" ''
      function print_email() {
        echo "Subject: [certspotter] $SUMMARY"
        echo "Mime-Version: 1.0"
        echo "Content-Type: text/plain; charset=US-ASCII"
        echo
        cat "$TEXT_FILENAME"
      }
      print_email | ${config.services.certspotter.sendmailPath} -i webmaster@example.org
    '')
  ];
}
```
