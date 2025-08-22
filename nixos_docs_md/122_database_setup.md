## Database Setup

You also need to configure a MariaDB or MySQL database and -user for Matomo yourself, and enter those credentials in your browser. You can use passwordless database authentication via the UNIX_SOCKET authentication plugin with the following SQL commands:

```programlisting

# For MariaDB

INSTALL PLUGIN unix_socket SONAME 'auth_socket';
CREATE DATABASE matomo;
CREATE USER 'matomo'@'localhost' IDENTIFIED WITH unix_socket;
GRANT ALL PRIVILEGES ON matomo.* TO 'matomo'@'localhost';

# For MySQL

INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
CREATE DATABASE matomo;
CREATE USER 'matomo'@'localhost' IDENTIFIED WITH auth_socket;
GRANT ALL PRIVILEGES ON matomo.* TO 'matomo'@'localhost';
```

Then fill in `matomo` as database user and database name, and leave the password field blank. This authentication works by allowing only the `matomo` unix user to authenticate as the `matomo` database user (without needing a password), but no other users. For more information on passwordless login, see [https://mariadb.com/kb/en/mariadb/unix_socket-authentication-plugin/](https://mariadb.com/kb/en/mariadb/unix_socket-authentication-plugin/).

Of course, you can use password based authentication as well, e.g. when the database is not on the same host.
