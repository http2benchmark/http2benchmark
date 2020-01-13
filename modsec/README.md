# README.md
## Installing and uninstalling modsecurity for LiteSpeed, Nginx, OpenLitespeed and Apache for http2benchmark
The purpose of this directory is to house the scripts to install and uninstall modsecurity into LiteSpeed Enterprise, Nginx, OpenLitespeed and Apache for the purposes of benchmarking.  It is part of the http2benchmark suite of benchmarks.

There are a number user scripts in this directory.  The first set of scripts allow you to configure a previously installed (by http2benchmark) web server for modsecurity using the OWASP rules.  Any of these scripts can be run in any order and they will install the OWASP rules (in a temp subdirectory of the execution directory) and modify the already installed server configuration to use them.
* **config_apache_modsec.sh**:  Installs and configures the modsecurity environment for the Apache web server.
* **config_lsws_modsec.sh**: Installs and configures the modsecurity environment for the Enterprise LiteSpeed web server.
* **config_nginx_modsec.sh**: Installs and configures the modsecurity environment for the Nginx web server.  This includes downloading the source code for Nginx, compiling the server and Nginx ModSecurity connector and installing them.
* **config_ols_modsec.sh**:  Installs and configures the modsecurity environment for the OpenLiteSpeed web server.

For example, to configure Enterprise LiteSpeed and Nginx for modsecurity, run the following scripts (as root):
`./config_lsws_modsec.sh`
`./config_nginx_modsec.sh`

Once the `./config.*` script has been run successfully, you can run the  `/opt/h2bench/benchmark.sh` script on the **client** machine and compare the various servers performance.  Since modsecurity is in effect you will see significantly different performance than without modsecurity installed and configured.

The following scripts will unconfigure the server definitions and return them to a non-modsecurity setup.  They do not completely delete the environment, just allow you to switch back and forth between modsecurity and non-modsecurity.  You can run the `config.*` script above to return it to a configured state.
* **unconfig_apache_modsec.sh**: Unconfigures Apache
* **unconfig_lsws_modsec.sh**: Unconfigures Enterprise LiteSpeed
* **unconfig_nginx_modsec.sh**: Unconfigures Nginx
* **unconfig_ols_modsec.sh**: Unconfigures OpenLiteSpeed

The following are composite scripts and are meant to be run the automate the install/configuration/uninstall/unconfiguration of all 4 servers supported.
* **modsec_ctl.sh**: When run with a control parameter does the requested function.  Must be run after running a successful `install_modsec.sh` or `config.*`.  When run after a `config.*` you must specify the server type after the control parameter (`apache`, `lsws`, `nginx`, or `openlitespeed`).  The control parameters are:
  - **unconfig**: Removes the modsecurity definitions from each of the server configurations, but leaves the files around which allow it to be run with the `config` parameter later.
  - **config**: If you have done an `unconfig`, reconfigures each of the server configurations for OWASP modsecurity.
  - **comodo**: If you have done an `unconfig`, reconfigures each of the server configurations for Comodo modsecurity.  For Litespeed Enterprise and Apache, you must have installed the v2 Apache Comodo definitions in a `comodo_apache` directory; for OpenLitespeed and Nginx you must have installed the v3 Nginx definitions in a `comodo_nginx` directory.
* **install_modsec.sh**: Installs and configures modsecurity for each of the servers installed
* **uninstall_modsec.sh**: Uninstalls and unconfigures modsecurity for each of the servers installed.  It does not completely return the system to a pre-install state as it leaves a few system libraries install, but all of the rules and configurations are removed.

What `install_modsec.sh` or the `config.*` scripts do is:
* Install compilation pre-requisites.
* Creates a `temp` directory to hold just about everything downloaded.
* Install the OWASP rules into it.
* (Nginx) Install the source for Nginx and it's modsecurity module into it,  compile them and copy them over.
* For each server it saves a copy of the existing configuration files and then modify them to use the installed modsecurity modules with OWASP rules.

What `unconfig.*` does is:
* Copy back the saved configuration files for each of the server types

What `uninstall_modsec.sh` does is:
* Copy back the saved configuration files for each of the server types
* Remove the temp directory to restore the system to it's preinstalled state.

What `modsec_ctl.sh` does is:
* **unconfig**: Copy back the saved configuration files for each of the server types or the specified server type.
* **config**: Saves a copy of the existing configuration files and reconfigures the server configuration files in the same way as `modsec.sh`
* **comodo**: Saves a copy of the existing configuration files and reconfigures the server configuration files specifically for the Comodo rule sets.
