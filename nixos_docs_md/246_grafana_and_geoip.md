## Grafana and GeoIP

The reports can be visualized and summarized with parsedmarc’s official Grafana dashboard. For all views to work, and for the data to be complete, GeoIP databases are also required. The following example shows a basic deployment where the provisioned Elasticsearch instance is automatically added as a Grafana datasource, and the dashboard is added to Grafana as well.

```programlisting
{
  services.parsedmarc = {
    enable = true;
    provision = {
      localMail = {
        enable = true;
        hostname = url;
      };
      grafana = {
        datasource = true;
        dashboard = true;
      };
    };
  };

  # Not required, but recommended for full functionality

  services.geoipupdate = {
    settings = {
      AccountID = 0;
      LicenseKey = "/path/to/license_key_file";
    };
  };

  services.grafana = {
    enable = true;
    addr = "0.0.0.0";
    domain = url;
    rootUrl = "https://" + url;
    protocol = "socket";
    security = {
      adminUser = "admin";
      adminPasswordFile = "/path/to/admin_password_file";
      secretKeyFile = "/path/to/secret_key_file";
    };
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    upstreams.grafana.servers."unix:/${config.services.grafana.socket}" = { };
    virtualHosts.${url} = {
      root = config.services.grafana.staticRootPath;
      enableACME = true;
      forceSSL = true;
      locations."/".tryFiles = "$uri @grafana";
      locations."@grafana".proxyPass = "http://grafana";
    };
  };
  users.users.nginx.extraGroups = [ "grafana" ];
}
```
