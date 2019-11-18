#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Modify Server for ModSecurity install OWasp script
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

if [ $# -ne 1 ] ; then
    fail_exit "Needs to be run by modsec.sh"
    exit 1
fi
OWASP_DIR="${1}"

mk_owasp_dir(){
    if [ -f $OWASP_DIR ] ; then
        rm -rf $OWASP_DIR
    fi
    silent mkdir -p $OWASP_DIR
    if [ $? -ne 0 ] ; then
        fail_exit "Unable to create directory: ${OWASP_DIR}"
    fi
}

install_owasp(){
    mk_owasp_dir
    silent pushd $OWASP_DIR
    silent git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git
    silent popd
}

configure_owasp(){
    silent pushd ${OWASP_DIR}
    echo "include modsecurity.conf
include owasp-modsecurity-crs/crs-setup.conf
include owasp-modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
include owasp-modsecurity-crs/rules/REQUEST-901-INITIALIZATION.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9001-DRUPAL-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9002-WORDPRESS-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9003-NEXTCLOUD-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9004-DOKUWIKI-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9005-CPANEL-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-903.9006-XENFORO-EXCLUSION-RULES.conf
include owasp-modsecurity-crs/rules/REQUEST-905-COMMON-EXCEPTIONS.conf
include owasp-modsecurity-crs/rules/REQUEST-910-IP-REPUTATION.conf
include owasp-modsecurity-crs/rules/REQUEST-911-METHOD-ENFORCEMENT.conf
include owasp-modsecurity-crs/rules/REQUEST-912-DOS-PROTECTION.conf
include owasp-modsecurity-crs/rules/REQUEST-913-SCANNER-DETECTION.conf
include owasp-modsecurity-crs/rules/REQUEST-920-PROTOCOL-ENFORCEMENT.conf
include owasp-modsecurity-crs/rules/REQUEST-921-PROTOCOL-ATTACK.conf
include owasp-modsecurity-crs/rules/REQUEST-930-APPLICATION-ATTACK-LFI.conf
include owasp-modsecurity-crs/rules/REQUEST-931-APPLICATION-ATTACK-RFI.conf
include owasp-modsecurity-crs/rules/REQUEST-932-APPLICATION-ATTACK-RCE.conf
include owasp-modsecurity-crs/rules/REQUEST-933-APPLICATION-ATTACK-PHP.conf
include owasp-modsecurity-crs/rules/REQUEST-934-APPLICATION-ATTACK-NODEJS.conf
include owasp-modsecurity-crs/rules/REQUEST-941-APPLICATION-ATTACK-XSS.conf
include owasp-modsecurity-crs/rules/REQUEST-942-APPLICATION-ATTACK-SQLI.conf
include owasp-modsecurity-crs/rules/REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION.conf
include owasp-modsecurity-crs/rules/REQUEST-944-APPLICATION-ATTACK-JAVA.conf
include owasp-modsecurity-crs/rules/REQUEST-949-BLOCKING-EVALUATION.conf
include owasp-modsecurity-crs/rules/RESPONSE-950-DATA-LEAKAGES.conf
include owasp-modsecurity-crs/rules/RESPONSE-951-DATA-LEAKAGES-SQL.conf
include owasp-modsecurity-crs/rules/RESPONSE-952-DATA-LEAKAGES-JAVA.conf
include owasp-modsecurity-crs/rules/RESPONSE-953-DATA-LEAKAGES-PHP.conf
include owasp-modsecurity-crs/rules/RESPONSE-954-DATA-LEAKAGES-IIS.conf
include owasp-modsecurity-crs/rules/RESPONSE-959-BLOCKING-EVALUATION.conf
include owasp-modsecurity-crs/rules/RESPONSE-980-CORRELATION.conf
include owasp-modsecurity-crs/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf">modsec_includes.conf
    echo "SecRuleEngine On">modsecurity.conf
    silent pushd owasp-modsecurity-crs
    silent mv crs-setup.conf.example crs-setup.conf
    silent pushd rules
    silent mv REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
    silent mv RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
    silent popd +2
}

main(){
    install_owasp
    configure_owasp
}
main
