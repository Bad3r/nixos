/*
  Package: mysql
  Description: MySQL Community Server distribution with client, server, and dump utilities.
  Homepage: https://www.mysql.com/
  Documentation: https://dev.mysql.com/doc/refman/8.4/en/
  Repository: https://github.com/mysql/mysql-server

  Summary:
    * Provides the MySQL 8.4 server daemon plus common client tools such as `mysql`, `mysqldump`, and `mysqladmin`.
    * Supports local administration, backups, imports, and application connectivity using the bundled client libraries and binaries.

  Options:
    mysql -u <user> -p: Connect to a MySQL server with the interactive client.
    mysqld --datadir=<path>: Start the server with an explicit data directory.
    mysqldump --databases <db>: Export one or more databases for backup or migration.

  Notes:
    * The pinned nixpkgs input exposes the package as `mysql84`, so this module keeps the stable `programs.mysql.extended` namespace while defaulting to that versioned attr.
*/
_:
let
  MysqlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mysql.extended;
    in
    {
      options.programs.mysql.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mysql.";
        };

        package = lib.mkPackageOption pkgs "mysql84" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mysql = MysqlModule;
}
