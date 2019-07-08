#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Client Script
# Version: 1.0
# *********************************************************************/
CMDFD='/opt'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
BENCH_SH="${CMDFD}/benchmark.sh"
ENVLOG="${ENVFD}/client/environment.log"
TEST_IP="${ENVFD}/ip.log"
TESTSERVERIP=''
CLIENTTOOL="${CMDFD}/tools"
CLIENTCF="${CLIENTTOOL}/config"
SSH=(ssh -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
JMFD='apache-jmeter'
JMPLAN='jmeter.jmx'
JMCFPATH="${CLIENTTOOL}/${JMFD}/bin/examples/${JMPLAN}"
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
CONF_LIST="urls.conf h2load.conf jmeter.jmx siege.conf wrk.conf"
SERVER_LIST="apache lsws nginx"

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

linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

checksystem(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        OSVER=$(awk '{print substr($4,0,1)}' /etc/redhat-release)
        if [ ${OSVER} -lt 7 ]; then 
            echoR "Your OS version is under 7, do you want to continue anyway? [y/N] "
            read TMP_YN
            if [[ ! "${TMP_YN}" =~ ^(y|Y) ]]; then
                exit 1
            fi    
        fi    
    elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
        OSNAME=ubuntu 
        OSVER=$(lsb_release -rs | awk -F. '{ print $1 }')
        if [ ${OSVER} -lt 18 ]; then 
            echoR "Your OS version is under 18, do you want to continue anyway? [y/N] "
            read TMP_YN
            if [[ ! "${TMP_YN}" =~ ^(y|Y) ]]; then
                exit 1
            fi    
        fi          
    else 
        echoR 'Please use CentOS or Ubuntu/Debian'
    fi      
}
checksystem
help_message() {
    case ${1} in
        "1")
        echoG 'Client installation finished'
        echoY "You can now run a benchmark with this command: ${BENCH_SH}"
        echoG "To customize the domain, please run this command: ${0} domain example.com"
        echoG "For more customization info, please run this command: ${BENCH_SH} -h"
        ;;
        "2")
        echo 'Please add the following key to ~/.ssh/authorized_keys on the Test server'
        echoY "$(cat ~/.ssh/http2.pub)" 
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
### bench_rsa, bench_rsa.pub
    echoG 'Generate client pub key'
    if [ -e ~/.ssh/${SSHKEYNAME} ]; then 
        rm -f ~/.ssh/${SSHKEYNAME}*
    fi    
    silent ssh-keygen -f ~/.ssh/${SSHKEYNAME} -P ""
    chmod 400 ~/.ssh/${SSHKEYNAME}*
    [[ -e ~/.ssh/${SSHKEYNAME} ]] && echoG 'Generate client pub key Success' || echoR 'Generate client pub key Failed'
}

ubuntu_install_pkg(){
### Basic Packages
    if [ ! -e /bin/wget ]; then 
        silent apt-get install wget curl software-properties-common -y
    fi
### Network Packages
    if [ -e /usr/bin/iperf ]; then 
        echoG 'Iperf already installed'
    else 
        echoG 'Install Iperf'
        silent apt-get install net-tools iperf -y
        [[ -e /usr/bin/iperf ]] && echoG 'Install Iperf Success' || echoR 'Install Iperf Failed' 
    fi    
}

centos_install_pkg(){
### Basic Packages
    if [ ! -e /bin/wget ]; then 
        silent yum install wget -y
    fi
### Network Packages
    if [ -e /usr/bin/iperf ]; then 
        echoG 'Iperf already installed'
    else 
        echoG 'Installing Iperf'
        silent yum install epel-release -y
        silent yum update -y
        silent yum install iperf -y
        [[ -e /usr/bin/iperf ]] && echoG 'Install Iperf Success' || echoR 'Install Iperf Failed' 
    fi    
}

ubuntu_install_siege(){
### Benchmark Tools
    ### Siege 
    if [ -e /usr/bin/siege ]; then 
        echoG 'Siege already installed'
    else 
        echoG 'Installing Siege'    
        silent apt-get install siege -y    
        [[ -e /usr/bin/siege ]] && echoG 'Install Siege Success' || echoR 'Install Siege Failed' 
    fi
}    

centos_install_siege(){
### Benchmark Tools
    ### Siege 
    if [ -e /usr/bin/siege ]; then 
        echoG 'Siege already installed'
    else 
        echoG 'Installing Siege'    
        silent yum install siege -y
        [[ -e /usr/bin/siege ]] && echoG 'Install Siege Success' || echoR 'Install Siege Failed' 
    fi
} 

ubuntu_install_h2load(){
    ### h2load
    if [ -e /usr/bin/h2load ]; then 
        echoG 'H2Load already installed'  
    else      
        echoG 'Installing h2load'
        silent apt-get install nghttp2-client -y             
        [[ -e /usr/bin/h2load ]] && echoG 'Install H2Load Success' || echoR 'Install H2Load Failed' 
    fi    
}

centos_install_h2load(){
    ### h2load
    if [ -e /usr/bin/h2load ]; then 
        echoG 'H2Load already installed'  
    else      
        echoG 'Installing h2load'
        silent yum install nghttp2 -y 
        [[ -e /usr/bin/h2load ]] && echoG 'Install H2Load Success' || echoR 'Install H2Load Failed' 
    fi    
}

ubuntu_install_wrk(){
    ### wrk
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
    ### wrk
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
    ### Jmeter
    if [ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]; then 
        echoG 'Jmeter already installed'
    else    
        echoG 'Installing Jmeter'
        cd ${CLIENTTOOL}/
        silent apt install openjdk-11-jre-headless -y     
        wget -q http://apache.osuosl.org//jmeter/binaries/apache-jmeter-5.1.1.tgz
        tar xf ${JMFD}-*.tgz
        rm -f ${JMFD}-*.tgz*
        mv ${JMFD}* ${JMFD}
        [[ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]] && echoG 'Install Jmeter Success' || echoR 'Install Jmeter Failed' 
    fi   
    mvexscript "../../tools/config/${JMPLAN}" "${JMCFPATH}"
}

centos_install_jemeter(){
    ### Jmeter
    if [ -e ${CLIENTTOOL}/${JMFD}/bin/jmeter.sh ]; then 
        echoG 'Jmeter already installed'
    else    
        echoG 'Installing Jmeter'
        cd ${CLIENTTOOL}/
        silent yum install java-11-openjdk-devel -y
        wget -q http://apache.osuosl.org//jmeter/binaries/apache-jmeter-5.1.1.tgz
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
### Check SSH
    echoG 'Start checking SSH...'   
    silent "${SSH[@]}" root@${1} "echo 'Test connection'"
    if [ ${?} != 0 ]; then 
        gen_sshkey
        help_message 2
        echoG 'Once complete, click ANY key to continue: '
        read ANYKEY
        loop_check_ssh ${1}
    fi     
    echoG 'Client to Server SSH is valid'
}
check_network(){
### Check bendwidth    
    echoG 'Checking network throughput...'
    ### Server side
    silent "${SSH[@]}" root@${1} "iperf -s >/dev/null 2>&1 &"
    silent "${SSH[@]}" root@${1} "ps aux | grep [i]perf"
    if [ ${?} = 0 ]; then
        ### Client side 
        echoG 'Client side Testing...'
        iperf -c ${1} -i1  >> ${ENVLOG}
        ### kill iperf process
        sleep 1
        "${SSH[@]}" root@${1} "kill -9 \$(ps aux | grep '[i]perf -s' | awk '{print \$2}')"
        echo -n 'Network traffic: '
        echoG "$(awk 'END{print $7,$8}' ${ENVLOG})"
    else
        echoR '[Failed] to Iperf due to connection issue'    
    fi
### Check latency 
    ping -c5 -w3 ${1} >> ${ENVLOG}
    echo -n 'Network latency: '
    echoG "$(awk -F '/' 'END{print $5}' ${ENVLOG}) ms"
}

check_spec(){
    ### Total Memory
    echo -n 'Client Server - Memory Size: '                             | tee -a ${ENVLOG}
    echoY $(awk '$1 == "MemTotal:" {print $2/1024 "MB"}' /proc/meminfo) | tee -a ${ENVLOG}
    ### Total CPU
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

mvclientscripts(){
    mvexscript '../../benchmark.sh' "${CMDFD}/"
    mvexscript '../../tools/parse.sh' "${CLIENTTOOL}/"
    for CONF in ${CONF_LIST}; do
        mvexscript "../../tools/config/${CONF}" "${CLIENTCF}/"
    done 
}

gen_domains(){
    for SERVER in ${SERVER_LIST}; do
        echo "${SERVER}: ${1}" >> ${CLIENTCF}/urls.conf
    done
}

custom_domains(){
    echoG "Custom domain to ${1}"
    TESTSERVERIP=$(cat ${TEST_IP})
    rm -f  ${CLIENTCF}/urls.conf
    gen_domains ${1}
    silent "${SSH[@]}" root@${TESTSERVERIP} "${CMDFD}/switch.sh custom_wpdomain ${1}"
    echoG "${1} domain setup finished"
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

main(){
    clean_log_fd
    create_log_fd
    [[ ${OSNAME} = 'centos' ]] && centos_main || ubuntu_main    
    loop_check_ip
    check_ssh ${TESTSERVERIP}
    check_server_install ${TESTSERVERIP}
    check_network ${TESTSERVERIP}
    check_spec ${TESTSERVERIP}
    mvclientscripts  
    gen_domains ${TESTSERVERIP}
    help_message 1
}

case ${1} in 
    custom_domains | domain) custom_domains ${2};;
    *) main ;;
esac    