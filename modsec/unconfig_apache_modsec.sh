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
    ./modsec_ctl.sh unconfig apache
    exit $?
elif [ $# -ne 3 ] ; then
    fail_exit "Needs to be run by uninstall_modsec.sh"
    exit 1
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
APADIR="${3}"

unconfig_apacheModSec(){
    silent grep "http2Benchmark" $APADIR/conf.d/mod_security.conf
    if [ $? -ne 0 ] ; then
        echoG "Apache already unconfigured for modsecurity"
        return 0
    fi
    if [ -f $APADIR/conf.d/mod_security.conf.nomodsec ] ; then
        cp -f $APADIR/conf.d/mod_security.conf.nomodsec $APADIR/conf.d/mod_security.conf
    else
        rm $APADIR/conf.d/mod_security.conf
    fi
}

unconfig_apacheModSec
