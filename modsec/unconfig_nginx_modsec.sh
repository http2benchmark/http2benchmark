#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity unconfig Nginx modsec
# *********************************************************************/

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

if [ $# -eq 0 ]; then
    ./modsec_ctl.sh unconfig nginx
    exit $?
elif [ $# -ne 3 ] ; then
    fail_exit "Needs to be run by uninstall_modsec.sh"
    exit 1
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
NGDIR="${3}"

unconfig_nginxModSec(){
    silent grep ngx_http_modsecurity_module.so $NGDIR/nginx.conf
    if [ $? -ne 0 ] ; then
        echoG "Nginx already unconfigured for modsecurity"
        return 0
    fi
    #nginx -s stop
    cp -f $NGDIR/nginx.conf.nomodsec $NGDIR/nginx.conf 
    cp -f $NGDIR/conf.d/default.conf.nomodsec $NGDIR/conf.d/default.conf 
    cp -f $NGDIR/conf.d/wordpress.conf.nomodsec $NGDIR/conf.d/wordpress.conf 
}

unconfig_nginxModSec
