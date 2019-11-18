#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity script
# *********************************************************************/
CMDFD='/opt'
ENVFD="${CMDFD}/env"
ENVLOG="${ENVFD}/server/environment.log"
CUSTOM_WP="${ENVFD}/custom_wp"
SERVERACCESS="${ENVFD}/serveraccess.txt"
DOCROOT='/var/www/html'
NGDIR='/etc/nginx'
APADIR='/etc/apache2'
LSDIR='/usr/local/entlsws'
OLSDIR='/usr/local/lsws'
#CADDIR='/etc/caddy'
#HTODIR='/etc/h2o'
#FPMCONF='/etc/php-fpm.d/www.conf'
USER='www-data'
GROUP='www-data'
#CERTDIR='/etc/ssl'
#MARIAVER='10.3'
#PHP_P='7'
#PHP_S='2'
REPOPATH=''
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SERVER_APACHE='apache'
SERVER_LSWS='lsws'
SERVER_NGINX='nginx'
SERVER_OLS='openlitespeed'
SERVER_LIST="$SERVER_LSWS $SERVER_NGINX $SERVER_OLS $SERVER_APACHE"
SERVERS_ALL='all'
#DOMAIN_NAME='benchmark.com'
#WP_DOMAIN_NAME='wordpress.benchmark.com'
declare -A WEB_ARR=( [lsws]=wp_lsws [nginx]=wp_nginx [openlitespeed]=wp_openlitespeed )

TEMP_DIR="${SCRIPTPATH}/temp"
OWASP_DIR="${TEMP_DIR}/owasp"

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

### Tools
echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}
echoR()
{
    echo -e "\033[38;5;203m${1}\033[39m"
}

fail_exit(){
    echoR "${1}"
}

fail_exit_fatal(){
    echoR "${1}"
    if [ $# -gt 1 ] ; then
        popd "+${2}"
    fi
    exit 1
}

check_system(){
    if [ -f /etc/redhat-release ] ; then
        grep -i fedora /etc/redhat-release >/dev/null 2>&1
        if [ ${?} = 1 ]; then
            OSNAME=centos
            USER='apache'
            GROUP='apache'
            REPOPATH='/etc/yum.repos.d'
            APACHENAME='httpd'
            APADIR='/etc/httpd'
            RED_VER=$(rpm -q --whatprovides redhat-release)
        else
            fail_exit "Please use CentOS or Ubuntu OS"
        fi    
    elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
        OSNAME=ubuntu 
        REPOPATH='/etc/apt/sources.list.d'
        APACHENAME='apache2'
        FPMCONF="/etc/php/${PHP_P}.${PHP_S}/fpm/pool.d/www.conf"
    else 
        fail_exit 'Please use CentOS or Ubuntu OS'
    fi      
}
check_system

if [ $# -eq 1 ]; then
    FOUND=0
    for SERVER in ${SERVER_LIST}; do
        if [ "$SERVER" = "$1" ]; then
            FOUND=1
            break;
        fi
    done
    if [ $FOUND -ne 1 ]; then
        fail_exit_fatal "Must be called with no parameters for all servers or a valid server"
    fi
elif [ $# -gt 1 ]; then
    fail_exit_fatal "Must be called with no parameters for all servers or a valid server"
else
    SERVER=$SERVERS_ALL
fi
echoG "Server set to $SERVER"

validate_servers(){
    if [ ! -f $SERVERACCESS ] ; then
        fail_exit_fatal 'Successfully install http2benchmark before installing ModSecurity for it'
    fi
    if [ "$SERVER" = "$SERVERS_ALL" ]; then
        if [ ! -d $APADIR -o ! -d $NGDIR -o ! -d $OLSDIR -o ! -d $LSDIR ] ; then
            fail_exit_fatal 'Successfully install http2benchmark (for Apache, OpenLitespeed, Enterprise Litespeed and Nginx) before installing ModSecurity for it'
        fi
    elif [ "$SERVER" = "$SERVER_APACHE" -a ! -d $APADIR ]; then
        fail_exit_fatal 'Successfully install http2benchmark for Apache before installing ModSecurity for it'
    elif [ "$SERVER" = "$SERVER_LSWS" -a ! -d $LSDIR ]; then
        fail_exit_fatal 'Successfully install http2benchmark for Litespeed Enterprise before installing ModSecurity for it'
    elif [ "$SERVER" = "$SERVER_NGINX" -a ! -d $NGDIR ]; then
        fail_exit_fatal 'Successfully install http2benchmark for Nginx before installing ModSecurity for it'
    elif [ "$SERVER" = "$SERVER_OLS" -a ! -d $OLSDIR ]; then
        fail_exit_fatal 'Successfully install http2benchmark for OpenLitespeed before installing ModSecurity for it'
    fi
}
validate_servers

validate_user(){
    if [ "$EUID" -ne 0 ] ; then
        fail_exit 'You must run this script as root'
    fi
}
validate_user

install_prereq(){
    if [ ${OSNAME} = 'centos' ]; then
        yum group install "Development Tools" -y
        yum install geoip geoip-devel yajl lmdb -y
    else
        apt install build-essential
        apt install libgeoip1 libgeoip-dev geoip-bin libyajl-dev lmdb-utils
    fi    
}

install_owasp(){
    if [ -d "$OWASP_DIR" ] ; then
        echoG "[OK] OWASP already installed"
        return 0
    fi
    if [ ! -x "${SCRIPTPATH}/install_owasp.sh" ] ; then
        fail_exit_fatal "[ERROR] Missing ${SCRIPTPATH}/install_owasp.sh script"
    fi
    PGM="${SCRIPTPATH}/install_owasp.sh"
    PARM1="${OWASP_DIR}"
    $PGM $PARM1
    if [ $? -gt 0 ] ; then
        fail_exit "install_owasp failed"
    fi
}

install_apacheModSec(){
    PGM="${SCRIPTPATH}/install_apache_modsec.sh"
    $PGM $APADIR $OSNAME
    if [ $? -gt 0 ] ; then
        fail_exit "install Apache failed"
    fi
}

install_nginxModSec(){
    if [ -f $NGDIR/modules/ngx_http_modsecurity_module.so ] ; then
        echoG 'Nginx modsecurity module already compiled and installed'
        return 0
    fi
    if [ ! -x "${SCRIPTPATH}/install_nginx_modsec.sh" ] ; then
        fail_exit_fatal "[ERROR] Missing ${SCRIPTPATH}/install_nginx_modsec.sh script"
    fi
    PGM="${SCRIPTPATH}/install_nginx_modsec.sh"
    PARM1="${TEMP_DIR}"
    PARM2="${OWASP_DIR}"
    $PGM $PARM1 $PARM2
    if [ $? -gt 0 ] ; then
        fail_exit "install Nginx failed"
    fi
}

config_apacheModSec(){
    silent grep "http2Benchmark" $APADIR/conf.d/mod_security.conf
    if [ $? -eq 0 ] ; then
        echoG "Apache already configured for modsecurity"
        return 0
    fi
    PGM="${SCRIPTPATH}/config_apache_modsec.sh"
    PARM1="${TEMP_DIR}"
    PARM2="${OWASP_DIR}"
    $PGM $PARM1 $PARM2 $APADIR
    if [ $? -gt 0 ] ; then
        fail_exit "config Apache failed"
    fi
}

config_nginxModSec(){
    silent grep ngx_http_modsecurity_module.so $NGDIR/nginx.conf
    if [ $? -eq 0 ] ; then
        echoG "Nginx already configured for modsecurity"
        return 0
    fi
    PGM="${SCRIPTPATH}/config_nginx_modsec.sh"
    PARM1="${TEMP_DIR}"
    PARM2="${OWASP_DIR}"
    $PGM $PARM1 $PARM2 $NGDIR
    if [ $? -gt 0 ] ; then
        fail_exit "config Nginx failed"
    fi
}

config_lswsModSec(){
    silent grep '<enableCensorship>1</enableCensorship>' $LSDIR/conf/httpd_config.xml
    if [ $? -eq 0 ] ; then
        echoG "LSWS already configured for modsecurity"
        return 0
    fi
    PGM="${SCRIPTPATH}/config_lsws_modsec.sh"
    PARM1="${TEMP_DIR}"
    PARM2="${OWASP_DIR}"
    $PGM $PARM1 $PARM2 $LSDIR
    if [ $? -gt 0 ] ; then
        fail_exit "config lsws failed"
    fi
}

config_olsModSec(){
    silent grep 'module mod_security {' $OLSDIR/conf/httpd_config.conf
    if [ $? -eq 0 ] ; then
        echoG "OpenLitespeed already configured for modsecurity"
        return 0
    fi
    PGM="${SCRIPTPATH}/config_ols_modsec.sh"
    PARM1="${TEMP_DIR}"
    PARM2="${OWASP_DIR}"
    $PGM $PARM1 $PARM2 $OLSDIR
    if [ $? -gt 0 ] ; then
        fail_exit "config OpenLitespeed failed"
    fi
}

main(){
    install_prereq
    install_owasp
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_APACHE" ]; then
        install_apacheModSec
    fi
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_NGINX" ]; then
        install_nginxModSec
    fi
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_APACHE" ]; then
        config_apacheModSec
    fi
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_NGINX" ]; then
        config_nginxModSec
    fi
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_LSWS" ]; then
        config_lswsModSec
    fi
    if [ "$SERVER" = "$SERVERS_ALL" -o "$SERVER" = "$SERVER_OLS" ]; then
        config_olsModSec
    fi
    echoG "Installation complete and successful"
}
main
