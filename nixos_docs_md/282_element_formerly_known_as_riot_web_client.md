## Element (formerly known as Riot) Web Client

[Element Web](https://github.com/element-hq/element-web) is the reference web client for Matrix and developed by the core team at matrix.org. Element was formerly known as Riot.im, see the [Element introductory blog post](https://element.io/blog/welcome-to-element/) for more information. The following snippet can be optionally added to the code before to complete the synapse installation with a web client served at `https://element.myhostname.example.org` and `https://element.example.org`. Alternatively, you can use the hosted copy at [https://app.element.io/](https://app.element.io/), or use other web clients or native client applications. Due to the `/.well-known` urls set up done above, many clients should fill in the required connection details automatically when you enter your Matrix Identifier. See [Try Matrix Now!](https://matrix.org/docs/projects/try-matrix-now.html) for a list of existing clients and their supported featureset.

```programlisting
{
  services.nginx.virtualHosts."element.${fqdn}" = {
    enableACME = true;
    forceSSL = true;
    serverAliases = [ "element.${config.networking.domain}" ];

    root = pkgs.element-web.override {
      conf = {
        default_server_config = clientConfig; # see `clientConfig` from the snippet above.

      };
    };
  };
}
```

### Note

The Element developers do not recommend running Element and your Matrix homeserver on the same fully-qualified domain name for security reasons. In the example, this means that you should not reuse the `myhostname.example.org` virtualHost to also serve Element, but instead serve it on a different subdomain, like `element.example.org` in the example. See the [Element Important Security Notes](https://github.com/element-hq/element-web/tree/v1.10.0#important-security-notes) for more information on this subject.
