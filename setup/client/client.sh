#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Client Script
# *********************************************************************/
CMDFD='/opt/h2bench'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
BENCH_SH="${CMDFD}/benchmark.sh"
ENVLOG="${ENVFD}/client/environment.log"
TEST_IP="${ENVFD}/ip.log"
TESTSERVERIP=''
HOST_FILE="/etc/hosts"
CLIENTTOOL="${CMDFD}/tools"
CLIENTCF="${CLIENTTOOL}/config"
SSH=(ssh -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
SSH_BATCH=(ssh -o 'BatchMode=yes' -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
JMFD='apache-jmeter'
JMPLAN='jmeter.jmx'
JMCFPATH="${CLIENTTOOL}/${JMFD}/bin/examples/${JMPLAN}"
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
CONF_LIST="urls.conf urls-wp.conf h2load.conf jmeter.jmx siege.conf wrk.conf"
SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
DOMAIN_NAME='benchmark.com'
WP_DOMAIN_NAME='wordpress.benchmark.com'

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}
create_log_fd(){
    mkdir -p ${ENVFD}/server
    mkdir -p ${ENVFD}/client
    mkdir -p ${CLIENTTOOL}
    mkdir -p ${CLIENTCF}
}

clean_log_fd(){
    rm -f ${ENVLOG}
}

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
echoB()
{
    echo -e "\033[1;3;94m${1}\033[0m"
}
echoNG() {
    echo -ne "\033[38;5;71m${1}\033[39m"
}

linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

check_os()
{
    OSTYPE=$(uname -m)
    if [ -f /etc/redhat-release ] ; then
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        if [ ${?} = 0 ] ; then
            OSNAMEVER=CENTOS${OSVER}
            OSNAME=centos
        fi
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        UBUNTU_V=$(grep 'DISTRIB_RELEASE' /etc/lsb-release | awk -F '=' '{print substr($2,1,2)}')
        if [ ${UBUNTU_V} = 14 ] ; then
            OSNAMEVER=UBUNTU14
            OSVER=trusty
        elif [ ${UBUNTU_V} = 16 ] ; then
            OSNAMEVER=UBUNTU16
            OSVER=xenial
        elif [ ${UBUNTU_V} = 18 ] ; then
            OSNAMEVER=UBUNTU18
            OSVER=bionic
        fi
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        DEBIAN_V=$(awk -F '.' '{print $1}' /etc/debian_version)
        if [ ${DEBIAN_V} = 7 ] ; then
            OSNAMEVER=DEBIAN7
            OSVER=wheezy
        elif [ ${DEBIAN_V} = 8 ] ; then
            OSNAMEVER=DEBIAN8
            OSVER=jessie
        elif [ ${DEBIAN_V} = 9 ] ; then
            OSNAMEVER=DEBIAN9
            OSVER=stretch
        elif [ ${DEBIAN_V} = 10 ] ; then
            OSNAMEVER=DEBIAN10
            OSVER=buster
        fi
    fi
    if [ "${OSNAMEVER}" = "" ] ; then
        echoR "Sorry, currently script only supports Centos(6-7), Debian(7-10) and Ubuntu(14,16,18)."
        exit 1
    else
        if [ "${OSNAME}" = "centos" ] ; then
            echoG "Current platform is ${OSNAME} ${OSVER}"
            if [ ${OSVER} = 8 ]; then
                echoR "Sorry, currently script only supports Centos(6-7), exit!!" 
                exit 1
                ### Many package/repo are not ready for it.
            fi    
        else
            export DEBIAN_FRONTEND=noninteractive
            echoG "Current platform is ${OSNAMEVER} ${OSNAME} ${OSVER}."
        fi
    fi
}


help_message() {
    case ${1} in
        "1")
        echoG "Client installation finished. For more information, please run command: ${BENCH_SH} -h"
        echo ''
        echo "Run a benchmark with this command:" $(echoY "${BENCH_SH}")
        echo ''
        ;;
        "2")
        echo "Please add the following key to $(echoB ~/.ssh/authorized_keys) on the Test server"
        echoY "$(cat ~/.ssh/${SSHKEYNAME}.pub)" 
        ;;
        "3")
        echo 'This script will install multiple benchmark tools and copy the benchmark script for testing'
        ;;
    esac
}

ubuntu_default_install(){
    silent DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' ${1}
}

ubuntu_sysupdate(){
    echoG 'System update'
    silent apt-get update
    ubuntu_default_install upgrade
    ubuntu_default_install dist-upgrade        
}

centos_sysupdate(){
    echoG 'System update'
    silent yum update -y    
}    

gen_sshkey(){
    echoG 'Generate client pub key'
    if [ -e ~/.ssh/${SSHKEYNAME} ]; then 
        rm -f ~/.ssh/${SSHKEYNAME}*
    fi    
    silent ssh-keygen -f ~/.ssh/${SSHKEYNAME} -P ""
    chmod 400 ~/.ssh/${SSHKEYNAME}*
    [[ -e ~/.ssh/${SSHKEYNAME} ]] && echoG 'Generate client pub key Success' || echoR 'Generate client pub key Failed'
}

ubuntu_install_pkg(){
    if [ ! -e /bin/wget ]; then 
        silent apt-get install wget curl software-properties-common -y
    fi
    if [ -e /usr/bin/iperf ]; then 
        echoG 'Iperf already installed'
    else 
        echoG 'Install Iperf'
        silent apt-get install net-tools iperf -y
        [[ -e /usr/bin/iperf ]] && echoG 'Install Iperf Success' || echoR 'Install Iperf Failed' 
    fi    
}

centos_install_pkg(){
    if [ ! -e /bin/wget ]; then 
        silent yum install wget -y
    fi
    if [ -e /usr/bin/iperf ] || [ -e /usr/bin/iperf3 ]; then 
        echoG 'Iperf already installed'
    else 
        echoG 'Installing Iperf'
        silent yum install epel-release -y
        silent yum update -y
        if [ "${OSNAMEVER}" = "CENTOS8" ] ; then
            silent yum install iperf3 -y
        else        
            silent yum install iperf -y
        fi    
        if [ -e /usr/bin/iperf ] || [ -e /usr/bin/iperf3 ]; then
            echoG 'Install Iperf Success'
        else
            echoR 'Install Iperf Failed' 
        fi    
    fi    
}

ubuntu_install_siege(){
    if [ -e /usr/bin/siege ]; then 
        echoG 'Siege already installed'
    else 
        echoG 'Installing Siege'    
        silent apt-get install siege -y    
        [[ -e /usr/bin/siege ]] && echoG 'Install Siege Success' || echoR 'Install Siege Failed' 
    fi
}    

centos_install_siege(){
    if [ -e /usr/bin/siege ]; then 
        echoG 'Siege already installed'
    else 
        echoG 'Installing Siege'    
        silent yum install siege -y
        [[ -e /usr/bin/siege ]] && echoG 'Install Siege Success' || echoR 'Install Siege Failed' 
    fi
} 

ubuntu_install_h2load(){
    if [ -e /usr/bin/h2load ]; then 
        echoG 'H2Load already installed'  
    else      
        echoG 'Installing h2load'
        silent apt-get install nghttp2-client -y             
        [[ -e /usr/bin/h2load ]] && echoG 'Install H2Load Success' || echoR 'Install H2Load Failed' 
    fi    
}

centos_install_h2load(){
    if [ -e /usr/bin/h2load ]; then 
        echoG 'H2Load already installed'  
    else      
        echoG 'Installing h2load'
        silent yum install nghttp2 -y 
        [[ -e /usr/bin/h2load ]] && echoG 'Install H2Load Success' || echoR 'Install H2Load Failed' 
    fi    
}

ubuntu_install_wrk(){
    if [ -e ${CLIENTTOOL}/wrk/wrk ]; then 
        echoG 'wrk already installed'  
    else      
        echoG 'Installing wrk'
        ubuntu_default_install 'install libssl-dev'
        silent apt-get install build-essential git -y
        cd ${CLIENTTOOL}/
        silent git clone https://github.com/wg/wrk.git wrk && cd wrk
        echoG 'Compiling wrk...'
        silent make    
        [[ -e ${CLIENTTOOL}/wrk/wrk ]] && echoG 'Install wrk Success' || echoR 'Install wrk Failed' 
    fi    
}

centos_install_wrk(){
    if [ -e ${CLIENTTOOL}/wrk/wrk ]; then 
        echoG 'wrk already installed'  
    else      
        echoG 'Installing wrk'
        silent yum groupinstall 'Development Tools' -y
        silent yum install openssl-devel git -y
        cd ${CLIENTTOOL}/
        silent git clone https://github.com/wg/wrk.git wrk && cd wrk
        echoG 'Compiling wrk...'
        silent make   
        [[ -e ${CLIENTTOOL}/wrk/wrk ]] && echoG 'Install wrk Success' || echoR 'Install wrk Failed' 
    fi    
}

ubuntu_install_jemeter(){
    if [ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]; then 
        echoG 'Jmeter already installed'
    else    
        echoG 'Installing Jmeter'
        cd ${CLIENTTOOL}/
        silent apt install openjdk-11-jre-headless -y     
        wget -q http://apache.osuosl.org//jmeter/binaries/apache-jmeter-5.2.tgz
        tar xf ${JMFD}-*.tgz
        rm -f ${JMFD}-*.tgz*
        mv ${JMFD}* ${JMFD}
        [[ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]] && echoG 'Install Jmeter Success' || echoR 'Install Jmeter Failed' 
    fi   
    mvexscript "../../tools/config/${JMPLAN}" "${JMCFPATH}"
}

centos_install_jemeter(){
    if [ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]; then 
        echoG 'Jmeter already installed'
    else    
        echoG 'Installing Jmeter'
        cd ${CLIENTTOOL}/
        silent yum install java-11-openjdk-devel -y
        wget -q http://apache.osuosl.org//jmeter/binaries/apache-jmeter-5.2.tgz
        tar xf ${JMFD}-*.tgz
        rm -f ${JMFD}-*.tgz*
        mv ${JMFD}* ${JMFD}
        [[ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]] && echoG 'Install Jmeter Success' || echoR 'Install Jmeter Failed' 
    fi   
    mvexscript "../../tools/config/${JMPLAN}" "${JMCFPATH}"
}

check_ip(){
    if [ $(echo ${1} | grep -o '\.' | wc -l) -ne 3 ]; then
        echoR "Parameter '${1}' does not contain 3 dots)."
        CHECKIP='false'
    elif [ $(echo ${1} | tr '.' ' ' | wc -w) -ne 4 ]; then
        echoR "Parameter '${1}' does not contain 4 octets)."
        CHECKIP='false'
    else
        for OCTET in $(echo ${1} | tr '.' ' '); do
            if ! [[ ${OCTET} =~ ^[0-9]+$ ]]; then
                echoR "Parameter '${1}' does not numeric)."
                CHECKIP='false'
            elif [[ ${OCTET} -lt 0 || ${OCTET} -gt 255 ]]; then
                echoR "Parameter '${1}' does not in range 0-255)."
                CHECKIP='false'
            fi
        done
    fi
}

loop_check_ip(){
    if [ -e "${TEST_IP}" ]; then  
        TESTSERVERIP=$(cat ${TEST_IP})
        echo -n "Do you wish to use existing ${TESTSERVERIP} to continue? [n/Y]: "
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(n|N) ]]; then
            rm -f ${TEST_IP} 
        else 
            TESTSERVERIP=${TESTSERVERIP}    
        fi   
    fi    
    if [ "${TESTSERVERIP}" = '' ]; then
        CHECKIP='false'
        while [ "${CHECKIP}" != 'true' ]; do
            CHECKIP='true'
            printf "%s"   "Please input target server IP to continue: "
            read TESTSERVERIP
            check_ip "${TESTSERVERIP}"
        done 
        echo ${TESTSERVERIP} > "${TEST_IP}"
        echoG "${TESTSERVERIP} is in valid IP format"
    fi    
}

check_server_install(){
    silent "${SSH[@]}" root@${1} "ls -l /${CMDFD}/switch.sh"
    if [ ${?} != 0 ]; then 
        echoR 'Please install server script on Test server'
        exit 1
    fi
}

loop_check_ssh(){
    CHECKSSH=false
    while [ "${CHECKSSH}" != 'true' ]; do
        silent "${SSH[@]}" root@${1} "echo 'Test connection'"
        [[ ${?} != 0 ]] && CHECKSSH='false' || CHECKSSH='true'
        if [ ${CHECKSSH} = false ]; then 
            echoR "SSH failed, please check again, then click ANY key to continue: "
            read ANYKEY
        fi    
    done 
}
check_ssh(){
    echoG 'Start checking SSH...'   
    silent "${SSH_BATCH[@]}" root@${1} "echo 'Test connection'"
    if [[ ${?} != 0 || ! -f ~/.ssh/${SSHKEYNAME}.pub ]]; then 
        gen_sshkey
        help_message 2
        echoG 'Once complete, click ANY key to continue: '
        read ANYKEY
        loop_check_ssh ${1}
    fi     
    echoG 'Client to Server SSH is valid'
}
check_network(){
    echoG 'Checking network throughput...'
    silent "${SSH[@]}" root@${1} "iperf -s >/dev/null 2>&1 &"
    silent "${SSH[@]}" root@${1} "ps aux | grep [i]perf"
    CHECK_CON=$(iperf -c ${1} -t 1 2>&1 >/dev/null)
    if [ $(echo ${CHECK_CON} | grep -i route | wc -l) = 0 ]; then
        echoG 'Client side Testing...'
        iperf -c ${1} -i1  >> ${ENVLOG}
        sleep 1
        "${SSH[@]}" root@${1} "kill -9 \$(ps aux | grep '[i]perf -s' | awk '{print \$2}')"
        echo -n 'Network traffic: '
        echoG "$(awk 'END{print $7,$8}' ${ENVLOG})"
    else
        echoR '[Failed] to Iperf due to connection issue, please check your firewall settings!'    
    fi
    ping -c5 -w3 ${1} >> ${ENVLOG}
    echo -n 'Network latency: '
    echoG "$(awk -F '/' 'END{print $5}' ${ENVLOG}) ms"
}

check_spec(){
    echo -n 'Client Server - Memory Size: '                             | tee -a ${ENVLOG}
    echoY $(awk '$1 == "MemTotal:" {print $2/1024 "MB"}' /proc/meminfo) | tee -a ${ENVLOG}
    echo -n 'Client Server - CPU number: '                              | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^CPU(s):' | awk '{print $NF}')                | tee -a ${ENVLOG}
    echo -n 'Client Server - CPU Thread: '                              | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^Thread(s) per core' | awk '{print $NF}')     | tee -a ${ENVLOG}
}

mvexscript(){
    cd ${SCRIPTPATH}/
    cp "${1}" "${2}"
    local FILENAME=$(echo "${1}" | awk -F '/' '{print $NF}')
    case "${FILENAME}" in
        *.sh) chmod +x ${2}/${FILENAME} ;; 
    esac
}

copy_tools(){
    mvexscript '../../benchmark.sh' "${CMDFD}/"
    mvexscript '../../default.profile' "${CMDFD}/"

    mvexscript '../../tools/parse.sh' "${CLIENTTOOL}/"
    mvexscript '../../tools/custom.sh' "${CLIENTTOOL}/"
    for CONF in ${CONF_LIST}; do
        mvexscript "../../tools/config/${CONF}" "${CLIENTCF}/"
    done 
}

addhosts(){
    echo "${TESTSERVERIP} ${DOMAIN_NAME}" >> ${HOST_FILE}
    echo "${TESTSERVERIP} ${WP_DOMAIN_NAME}" >> ${HOST_FILE}
}

gen_domains(){
    for SERVER in ${SERVER_LIST}; do
        echo "${SERVER}: ${DOMAIN_NAME}" >> ${CLIENTCF}/urls.conf
        echo "${SERVER}: ${1}" >> ${CLIENTCF}/urls-wp.conf
    done
}

prepare(){
    check_os
    clean_log_fd
    create_log_fd
}

ubuntu_main(){
    ubuntu_sysupdate
    ubuntu_install_pkg
    ubuntu_install_siege
    ubuntu_install_h2load
    ubuntu_install_wrk
    ubuntu_install_jemeter
}

centos_main(){
    centos_sysupdate
    centos_install_pkg
    centos_install_siege
    centos_install_h2load
    centos_install_wrk
    centos_install_jemeter
}

main_check(){
    loop_check_ip
    check_ssh ${TESTSERVERIP}
    check_server_install ${TESTSERVERIP}
    check_network ${TESTSERVERIP}
    check_spec ${TESTSERVERIP}
}

main(){
    prepare
    [[ ${OSNAME} = 'centos' ]] && centos_main || ubuntu_main    
    main_check
    copy_tools
    addhosts
    gen_domains ${WP_DOMAIN_NAME}
    help_message 1
}

case ${1} in
    -[hH] | -help | --help)
        help_message 3
        ;;
    *)    
        main    
        ;;
esac        
