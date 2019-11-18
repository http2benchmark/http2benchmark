#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity config Lsws modsec
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
    ./modsec_ctl.sh unconfig lsws
    exit $?
elif [ $# -ne 3 ] ; then
    fail_exit "Needs to be run by uninstall_modsec.sh"
    exit 1
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
LSDIR="${3}"

unconfig_lswsModSec(){
    silent grep '<enableCensorship>0</enableCensorship>' $LSDIR/conf/httpd_config.xml
    if [ $? -eq 0 ] ; then
        echoG "LSWS already unconfigured for modsecurity"
        return 0
    fi
    #$LSDIR/bin/lswsctrl stop
    cp -f $LSDIR/conf/httpd_config.xml.nomodsec $LSDIR/conf/httpd_config.xml
}

unconfig_lswsModSec
