#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity config Apache modsec
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
        ./modsec.sh "apache"
        exit $?
    fi
    fail_exit_fatal "Needs to be run by modsec.sh"
    exit 1
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
APADIR="${3}"
if [ $# -eq 4 ] ; then
    COMODO=1
else
    COMODO=0
fi

config_apacheModSec(){
    silent grep "http2Benchmark" $APADIR/conf.d/mod_security.conf
    if [ $? -eq 0 ] ; then
        echoG "Apache already configured for modsecurity"
        return 0
    fi
    if [ -f $APADIR/conf.d/mod_security.conf ] ; then
        cp -f $APADIR/conf.d/mod_security.conf $APADIR/conf.d/mod_security.conf.nomodsec
    fi
    if [ $COMODO -eq 1 ] ; then
        echo -e "<IfModule mod_security2.c>\n    # http2Benchmark Comodo Rules\n    SecDataDir $OWASP_DIR\n    Include $OWASP_DIR/*.conf\n</IfModule>\n" > $APADIR/conf.d/mod_security.conf
    else
        echo -e "<IfModule mod_security2.c>\n    # http2Benchmark OWASP Rules\n    SecDataDir $OWASP_DIR/owasp-modsecurity-crs/rules\n    #Include $OWASP_DIR/modsec_includes.conf\n    Include $OWASP_DIR/modsecurity.conf\n    Include $OWASP_DIR/owasp-modsecurity-crs/crs-setup.conf\n    Include $OWASP_DIR/owasp-modsecurity-crs/rules/*.conf\n</IfModule>\n" > $APADIR/conf.d/mod_security.conf
    fi
}

config_apacheModSec
