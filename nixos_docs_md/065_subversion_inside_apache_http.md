## Subversion inside Apache HTTP

This section focuses on configuring a web-based server on top of the Apache HTTP server, which uses [WebDAV](http://www.webdav.org/)/[DeltaV](http://www.webdav.org/deltav/WWW10/deltav-intro.htm) for communication.

For more information on the general setup, please refer to the [the appropriate section of the Subversion book](https://svnbook.red-bean.com/en/1.7/svn-book.html#svn.serverconfig.httpd).

To configure, include in `/etc/nixos/configuration.nix` code to activate Apache HTTP, setting [`services.httpd.adminAddr`](options.html#opt-services.httpd.adminAddr) appropriately:

```programlisting
{
  services.httpd.enable = true;
  services.httpd.adminAddr = "...";
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
```

For a simple Subversion server with basic authentication, configure the Subversion module for Apache as follows, setting `hostName` and `documentRoot` appropriately, and `SVNParentPath` to the parent directory of the repositories, `AuthzSVNAccessFile` to the location of the `.authz` file describing access permission, and `AuthUserFile` to the password file.

```programlisting
{
  services.httpd.extraModules = [
    # note that order is *super* important here

    {
      name = "dav_svn";
      path = "${pkgs.apacheHttpdPackages.subversion}/modules/mod_dav_svn.so";
    }
    {
      name = "authz_svn";
      path = "${pkgs.apacheHttpdPackages.subversion}/modules/mod_authz_svn.so";
    }
  ];
  services.httpd.virtualHosts = {
    "svn" = {
      hostName = HOSTNAME;
      documentRoot = DOCUMENTROOT;
      locations."/svn".extraConfig = ''
        DAV svn
        SVNParentPath REPO_PARENT
        AuthzSVNAccessFile ACCESS_FILE
        AuthName "SVN Repositories"
        AuthType Basic
        AuthUserFile PASSWORD_FILE
        Require valid-user
      '';
    };
  };
}
```

The key `"svn"` is just a symbolic name identifying the virtual host. The `"/svn"` in `locations."/svn".extraConfig` is the path underneath which the repositories will be served.

[This page](https://wiki.archlinux.org/index.php/Subversion) explains how to set up the Subversion configuration itself. This boils down to the following:

Underneath `REPO_PARENT` repositories can be set up as follows:

```programlisting
$ svn create REPO_NAME
```

Repository files need to be accessible by `wwwrun`:

```programlisting
$ chown -R wwwrun:wwwrun REPO_PARENT
```

The password file `PASSWORD_FILE` can be created as follows:

```programlisting
$ htpasswd -cs PASSWORD_FILE USER_NAME
```

Additional users can be set up similarly, omitting the `c` flag:

```programlisting
$ htpasswd -s PASSWORD_FILE USER_NAME
```

The file describing access permissions `ACCESS_FILE` will look something like the following:

```programlisting
[/]
* = r

[REPO_NAME:/]
USER_NAME = rw
```

The Subversion repositories will be accessible as `http://HOSTNAME/svn/REPO_NAME`.
