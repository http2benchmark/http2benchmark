#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity config Nginx modsec
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

if [ $# -lt 3 ] ; then
    if [ $# -eq 0 ]; then
        ./modsec.sh "nginx"
        exit $?
    fi
    fail_exit_fatal "Needs to be run by modsec.sh"
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
NGDIR="${3}"
if [ $# -eq 4 ] ; then
    COMODO=1
else
    COMODO=0
fi

config_nginxModSec(){
    silent grep ngx_http_modsecurity_module.so $NGDIR/nginx.conf
    if [ $? -eq 0 ] ; then
        echoG "Nginx already configured for modsecurity"
        return 0
    fi
    cp -f $NGDIR/nginx.conf $NGDIR/nginx.conf.nomodsec
    cp -f $NGDIR/conf.d/default.conf $NGDIR/conf.d/default.conf.nomodsec
    cp -f $NGDIR/conf.d/wordpress.conf $NGDIR/conf.d/wordpress.conf.nomodsec
    sed -i '1iload_module modules/ngx_http_modsecurity_module.so;' $NGDIR/nginx.conf
    if [ $COMODO -eq 1 ] ; then
        sed -i "s=server {=server {\n    modsecurity on;\n    modsecurity_rules_file $OWASP_DIR/rules.conf.main;=g" $NGDIR/conf.d/default.conf
        sed -i "s=server {=server {\n    modsecurity on;\n    modsecurity_rules_file $OWASP_DIR/rules.conf.main;=g" $NGDIR/conf.d/wordpress.conf
    else
        sed -i "s=server {=server {\n    modsecurity on;\n    modsecurity_rules_file $OWASP_DIR/modsec_includes.conf;=g" $NGDIR/conf.d/default.conf
        sed -i "s=server {=server {\n    modsecurity on;\n    modsecurity_rules_file $OWASP_DIR/modsec_includes.conf;=g" $NGDIR/conf.d/wordpress.conf
    fi
}

config_nginxModSec
