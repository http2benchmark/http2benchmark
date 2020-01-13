#!/bin/bash
CMDFD='/opt/h2bench'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
CUSTOM_WP="${ENVFD}/custom_wp"
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

echoBG() {
    echo -e "\033[38;5;47m${1}\033[39m"
}

help_message() {
    case ${1} in
        "1")
        echo '###############################################################################################'
        echo "To custom wordpress domain, run: " 
        echoBG "bash ${CLIENTTOOL}/custom.sh domain [example.com]"
        echo ''
        echo "To import your wordpress site to test, please access to your wordpress folder and run: "
        echoBG "tar -czvf mysite.tar.gz ."
        echo 'Then export the wordpress database, run: '
        echoBG "mysqldump -u root -p[ROOT_PASSWORD] [DB_NAME] > wordpressdb.sql"
        echo "upload both of your 'mysite.tar.gz' and 'mywordpressdb.sql' to the test server folder: ${CUSTOM_WP}"
        echo "Execute the auto wordpress migration please run: "
        echoBG "bash ${CLIENTTOOL}/custom.sh wordpress"
        echo '###############################################################################################'
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

custom_wp(){
    echoG "Custom wordpress ..."
    "${SSH[@]}" root@${TESTSERVERIP} "${CMDFD}/customwp.sh custom_wordpress" > /dev/null 2>&1
    echoG "WordPress setup finished"    
}

case ${1} in 
    [dD]omain ) custom_domains ${2};;
    [wW]*) custom_wp;;
    *) help_message 1 ;;
esac  
