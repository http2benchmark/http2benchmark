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

if [ $# -lt 3 ] ; then
    if [ $# -eq 0 ]; then
        ./modsec.sh "lsws"
        exit $?
    fi
    fail_exit_fatal "Needs to be run by modsec.sh"
fi
TEMP_DIR="${1}"
OWASP_DIR="${2}"
LSDIR="${3}"
if [ $# -eq 4 ] ; then
    COMODO=1
else
    COMODO=0
fi

config_lswsModSec(){
    silent grep '<enableCensorship>1</enableCensorship>' $LSDIR/conf/httpd_config.xml
    if [ $? -eq 0 ] ; then
        echoG "LSWS already configured for modsecurity"
        return 0
    fi
    cp -f $LSDIR/conf/httpd_config.xml $LSDIR/conf/httpd_config.xml.nomodsec
    sed -i "s=<enableCensorship>0</enableCensorship>=<enableCensorship>1</enableCensorship>=" $LSDIR/conf/httpd_config.xml
    if [ $COMODO -eq 1 ] ; then
        sed -i "s=</censorshipControl>=</censorshipControl>\n    <censorshipRuleSet>\n      <name>ModSec</name>\n      <enabled>1</enabled>\n      <ruleSet>include $OWASP_DIR/rules.conf.main</ruleSet>\n    </censorshipRuleSet>=" $LSDIR/conf/httpd_config.xml
    else
        sed -i "s=</censorshipControl>=</censorshipControl>\n    <censorshipRuleSet>\n      <name>ModSec</name>\n      <enabled>1</enabled>\n      <ruleSet>include $OWASP_DIR/modsec_includes.conf</ruleSet>\n    </censorshipRuleSet>=" $LSDIR/conf/httpd_config.xml
    fi
}

config_lswsModSec
