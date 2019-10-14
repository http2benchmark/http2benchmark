#!/bin/bash
CMDFD='/opt'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
BENCH_SH="${CMDFD}/benchmark.sh"
ENVLOG="${ENVFD}/client/environment.log"
TEST_IP="${ENVFD}/ip.log"
HOST_FILE="/etc/hosts"
TESTSERVERIP=''
CLIENTTOOL="${CMDFD}/tools"
CLIENTCF="${CLIENTTOOL}/config"
SSH=(ssh -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
SSH_BATCH=(ssh -o 'BatchMode=yes' -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
TESTSERVERIP=$(cat ${TEST_IP})

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}

help_message() {
    case ${1} in
        "1")
        echoY "Usage: [Command] [parameter]"
        echoY "Commands: domain [example.com]"
        ;;
    esac
}

rdlastfield(){
    if [ -e "${2}" ]; then
        LASTFIELD=$(grep ${1} ${2} | awk '{print $NF}')
    else
        LASTFIELD='NA'
        echoR "${2} not found"
    fi
}

rmhosts(){
    for SERVER in ${SERVER_LIST}; do
        rdlastfield ${SERVER} "${CLIENTCF}/urls-wp.conf"
        DOMAIN_NAME=${LASTFIELD}
        sed -i "/${DOMAIN_NAME}/ d" ${HOST_FILE}
    done
}

addhosts(){
    echo "${TESTSERVERIP} ${1}" >> ${HOST_FILE}
}

gen_domains(){
    rm -f  ${CLIENTCF}/urls-wp.conf
    for SERVER in ${SERVER_LIST}; do
        echo "${SERVER}: ${1}" >> ${CLIENTCF}/urls-wp.conf
    done
}

custom_domains(){
    echoG "Custom domain to ${1} ..."
    rmhosts
    "${SSH[@]}" root@${TESTSERVERIP} "${CMDFD}/switch.sh custom_domain ${DOMAIN_NAME} ${1}" > /dev/null 2>&1
    gen_domains ${1}
    addhosts ${1}
    echoG "${1} domain setup finished"
}

case ${1} in 
    domain | Domain) custom_domains ${2};;
    *) help_message 1 ;;
esac  