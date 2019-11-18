#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity contro script.      
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
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SERVER_APACHE='apache'
SERVER_LSWS='lsws'
SERVER_NGINX='nginx'
SERVER_OLS='openlitespeed'
SERVER_LIST="$SERVER_LSWS $SERVER_NGINX $SERVER_OLS $SERVER_APACHE"

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

usage(){
    echoR "Usage:"
    echoR "  ./modsec_ctl.sh config   - Assuming you have run ./modsec.sh configures the servers to use the OWASP rules"
    echoR "  ./modsec_ctl.sh comodo   - Assuming you have run ./modsec.sh and copied the comodo rules into 'comodo_apache' and 'comodo_nginx' directories configures the server to use them"
    echoR "  ./modsec_ctl.sh unconfig - Assuming you have installed the rules, removes the configuration, but leaves the rules around to be reconfigured later"
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

if [ $# -lt 1 ] ; then
    usage
    fail_exit_fatal "Needs to be run with a parameter"
elif [ $# -eq 2 ] ; then
    FOUND=0
    for SERVER in ${SERVER_LIST}; do
        if [ "$2" = "$SERVER" ]; then
            SERVER_LIST=$SERVER
            FOUND=1
            break
        fi
    done
    if [ $FOUND -eq 0 ]; then
        usage
        fail_exit_fatal "You specified an unknown server to control on the command line"
    fi
elif [ $# -gt 2 ]; then
    usage
    fail_exit_fatal "You specified too many parameters on the command line"
fi

if [ ! -f $SERVERACCESS -o ! -d $NGDIR -o ! -d $LSDIR ] ; then
    fail_exit_fatal 'Successfully install http2benchmark before installing ModSecurity for it'
fi
if [ ! -d $TEMP_DIR -o ! -d $OWASP_DIR ] ; then
    fail_exit_fatal 'Run modsec.sh before running modsec_ctl'
fi

check_server(){
    if [ ${1} = 'lsws' ] ; then
        SCRIPT="config_lsws_modsec.sh"
        SERVER_DIR="$LSDIR"
    elif [ ${1} = 'nginx' ] ; then
        SCRIPT="config_nginx_modsec.sh"
        SERVER_DIR="$NGDIR"
    elif [ ${1} = 'openlitespeed' ] ; then
        SCRIPT="config_ols_modsec.sh"
        SERVER_DIR="$OLSDIR"
    elif [ ${1} = 'apache' ] ; then
        SCRIPT="config_apache_modsec.sh"
        SERVER_DIR="$APADIR"
    else
        fail_exit_fatal "Internal error - unknown server type: ${1}"
    fi
}

check_comodo(){
    if [ ${1} = 'lsws' -o ${1} = 'apache' ] ; then
        COMODO_DIR='comodo_apache'
    else
        COMODO_DIR='comodo_nginx'
    fi
    if [ ! -d "$COMODO_DIR" ] ; then
        fail_exit_fatal "You must install your rules in the $COMODO_DIR directory"
    fi
    if [ ! -f "$COMODO_DIR/rules.conf.main" ] ; then
        fail_exit_fatal "You must have the rules.conf.main in this directory"
    fi
}

case "$1" in
    config)
        FAILED=0
        for SERVER in ${SERVER_LIST}; do
            check_server $SERVER
            if [ $? -eq 0 ] ; then
                PGM="${SCRIPTPATH}/$SCRIPT"
                PARM1="${TEMP_DIR}"
                PARM2="${OWASP_DIR}"
                $PGM $PARM1 $PARM2 $SERVER_DIR
                if [ $? -gt 0 ] ; then
                    fail_exit "config $SERVER failed"
                    FAILED=1
                fi
            fi
        done
        if [ $FAILED -eq 1 ] ; then
            echoY "config completed with some failures"
        else
            echoG "config completed successfully"
        fi
        ;;
        
    comodo)
        FAILED=0
        for SERVER in ${SERVER_LIST}; do
            check_server $SERVER
            check_comodo $SERVER
            if [ $? -eq 0 ] ; then
                PGM="${SCRIPTPATH}/$SCRIPT"
                PARM1="${TEMP_DIR}"
                PARM2="${SCRIPTPATH}/${COMODO_DIR}"
                $PGM $PARM1 $PARM2 $SERVER_DIR 1
                if [ $? -gt 0 ] ; then
                    fail_exit "comodo config $SERVER failed"
                    FAILED=1
                fi
            fi
        done
        if [ $FAILED -eq 1 ] ; then
            echoY "comodo config completed with some failures"
        else
            echoG "comodo config completed successfully"
        fi
        ;;
        
    unconfig)
        FAILED=0
        for SERVER in ${SERVER_LIST}; do
            check_server $SERVER
            if [ $? -eq 0 ] ; then
                PGM="${SCRIPTPATH}/un$SCRIPT"
                PARM1="${TEMP_DIR}"
                PARM2="${OWASP_DIR}"
                $PGM $PARM1 $PARM2 $SERVER_DIR
                if [ $? -gt 0 ] ; then
                    fail_exit "config $SERVER failed"
                    FAILED=1
                fi
            fi
        done
        if [ $FAILED -eq 1 ] ; then
            echoY "unconfig completed with some failures"
        else
            echoG "unconfig completed successfully"
        fi
        ;;
        
    *)
        usage
        fail_exit_fatal "Invalid parameter"
        ;;
esac    
