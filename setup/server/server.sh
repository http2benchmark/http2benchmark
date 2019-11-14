#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Server Script
# *********************************************************************/
CMDFD='/opt'
ENVFD="${CMDFD}/env"
ENVLOG="${ENVFD}/server/environment.log"
CUSTOM_WP="${ENVFD}/custom_wp"
SERVERACCESS="${ENVFD}/serveraccess.txt"
DOCROOT='/var/www/html'
NGDIR='/etc/nginx'
APADIR='/etc/apache2'
LSDIR='/usr/local/entlsws'
OLSDIR='/usr/local/lsws'
CADDIR='/etc/caddy'
HTODIR='/etc/h2o'
FPMCONF='/etc/php-fpm.d/www.conf'
USER=''
GROUP=''
CERTDIR='/etc/ssl'
MARIAVER='10.3'
PHP_P='7'
PHP_S='2'
REPOPATH=''
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
DOMAIN_NAME='benchmark.com'
WP_DOMAIN_NAME='wordpress.benchmark.com'
OSNAMEVER=''
OSNAME=''
OSVER=''
declare -A WEB_ARR=( [apache]=wp_apache [lsws]=wp_lsws [nginx]=wp_nginx [openlitespeed]=wp_openlitespeed [caddy]=wp_caddy [h2o]=wp_h2o )

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

create_log_fd(){
    if [ ! -d ${DOCROOT} ]; then 
        mkdir -p ${DOCROOT}
    fi    
    mkdir -p ${ENVFD}/server
    mkdir -p ${CMDFD}/log
}

clean_log_fd(){
    rm -rf ${ENVLOG}
    rm -f ${SERVERACCESS}  
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

get_ip(){
    if [ -e /sys/devices/virtual/dmi/id/product_uuid ] && [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ]; then
        MYIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
    elif [ "$(sudo dmidecode -s bios-vendor)" = 'Google' ]; then
        MYIP=$(curl -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        MYIP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")  
    elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ]; then
        MYIP=$(curl -s http://100.100.100.200/latest/meta-data/eipv4)              
    else
        MYIP=$(ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')
    fi
}

line_change(){
    LINENUM=$(grep -v '#' ${2} | grep -n "${1}" | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi  
}

check_os()
{
    OSTYPE=$(uname -m)
    MARIADBCPUARCH=
    if [ -f /etc/redhat-release ] ; then
        OSVER=$(cat /etc/redhat-release | awk '{print substr($4,1,1)}')
        if [ ${?} = 0 ] ; then
            OSNAMEVER=CENTOS${OSVER}
            OSNAME=centos
            rpm -ivh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el${OSVER}.noarch.rpm >/dev/null 2>&1
        fi
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu
        wget -qO - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash >/dev/null 2>&1
        UBUNTU_V=$(grep 'DISTRIB_RELEASE' /etc/lsb-release | awk -F '=' '{print substr($2,1,2)}')
        if [ ${UBUNTU_V} = 14 ] ; then
            OSNAMEVER=UBUNTU14
            OSVER=trusty
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
        elif [ ${UBUNTU_V} = 16 ] ; then
            OSNAMEVER=UBUNTU16
            OSVER=xenial
            MARIADBCPUARCH="arch=amd64,i386,ppc64el"
        elif [ ${UBUNTU_V} = 18 ] ; then
            OSNAMEVER=UBUNTU18
            OSVER=bionic
            MARIADBCPUARCH="arch=amd64"
        fi
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
        wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash
        DEBIAN_V=$(awk -F '.' '{print $1}' /etc/debian_version)
        if [ ${DEBIAN_V} = 7 ] ; then
            OSNAMEVER=DEBIAN7
            OSVER=wheezy
            MARIADBCPUARCH="arch=amd64,i386"
        elif [ ${DEBIAN_V} = 8 ] ; then
            OSNAMEVER=DEBIAN8
            OSVER=jessie
            MARIADBCPUARCH="arch=amd64,i386"
        elif [ ${DEBIAN_V} = 9 ] ; then
            OSNAMEVER=DEBIAN9
            OSVER=stretch
            MARIADBCPUARCH="arch=amd64,i386"
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
                ### Many package/repo are not ready for it.
            fi    
        else
            export DEBIAN_FRONTEND=noninteractive
            echoG "Current platform is ${OSNAMEVER} ${OSNAME} ${OSVER}."
        fi
    fi
}
check_os

path_update(){
    if [ "${OSNAME}" = "centos" ] ; then
        USER='apache'
        GROUP='apache'
        REPOPATH='/etc/yum.repos.d'
        APACHENAME='httpd'
        APADIR='/etc/httpd'
        RED_VER=$(rpm -q --whatprovides redhat-release)
    elif [ "${OSNAME}" = 'ubuntu' ] || [ "${OSNAME}" = 'debian' ]; then
        USER='www-data'
        GROUP='www-data'
        REPOPATH='/etc/apt/sources.list.d'
        APACHENAME='apache2'
        FPMCONF="/etc/php/${PHP_P}.${PHP_S}/fpm/pool.d/www.conf"
    fi      
}
path_update

KILL_PROCESS(){
    PROC_NUM=$(pidof ${1})
    if [ ${?} = 0 ]; then
        kill -9 ${PROC_NUM}
    fi    
}

ubuntu_sysupdate(){
    echoG 'System update'
    silent apt-get update
    silent DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' upgrade
    silent DEBIAN_FRONTEND=noninteractive apt-get -y \
    -o Dpkg::Options::='--force-confdef' \
    -o Dpkg::Options::='--force-confold' dist-upgrade        
}

centos_sysupdate(){
    echoG 'System update'
    silent yum update -y    
    setenforce 0
}    

backup_old(){
    if [ -f ${1} ] && [ ! -f ${1}_old ]; then
       mv ${1} ${1}_old
    fi
}

gen_pwd(){
    if [ ! -s ${SERVERACCESS} ]; then 
        ADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
        MYSQL_ROOT_PASS=$(openssl rand -hex 24)
        MYSQL_USER_PASS=$(openssl rand -hex 24)
    else
        ADMIN_PASS=$(grep LSWS_admin_PASS ${SERVERACCESS} | awk '{print $2}')
        MYSQL_ROOT_PASS=$(grep MYSQL_root_PASS ${SERVERACCESS} | awk '{print $2}')
        MYSQL_USER_PASS=$(grep MYSQL_wordpress_PASS ${SERVERACCESS} | awk '{print $2}')    
    fi    
}

display_pwd(){
    echoY "LSWS_admin_PASS:           ${ADMIN_PASS}" 
    echo  "LSWS_admin_PASS:           ${ADMIN_PASS}"     >> ${SERVERACCESS}
    echoY "WordPress_admin_PASS:      ${ADMIN_PASS}"     
    echo  "WordPress_admin_PASS:      ${ADMIN_PASS}"     >> ${SERVERACCESS}
    echoY "MYSQL_root_PASS:           ${MYSQL_ROOT_PASS}"
    echo  "MYSQL_root_PASS:           ${MYSQL_ROOT_PASS}">> ${SERVERACCESS}
    echoY "MYSQL_wordpress_PASS:      ${MYSQL_USER_PASS}"
    echo  "MYSQL_wordpress_PASS:      ${MYSQL_USER_PASS}">> ${SERVERACCESS}
    echoG "Access infomation stored in ${SERVERACCESS}"
}

checkweb(){
    if [ ${1} = 'lsws' ] || [ ${1} = 'ols' ]; then
        ps -ef | grep lshttpd | grep -v grep >/dev/null 2>&1
    else
        ps -ef | grep "${1}" | grep -v grep >/dev/null 2>&1
    fi    
    if [ ${?} = 0 ]; then 
        echoG "${1} process is running!"
        echoG 'Stop web service temporary'
        if [ "${1}" = 'lsws' ]; then 
           PROC_NAME='lshttpd'
            silent ${LSDIR}/bin/lswsctrl stop
            ps aux | grep '[w]swatch.sh' >/dev/null 2>&1
            if [ ${?} = 0 ]; then
                kill -9 $(ps aux | grep '[w]swatch.sh' | awk '{print $2}')
            fi    
        elif [ "${1}" = 'ols' ]; then 
            PROC_NAME='lshttpd'
            silent ${OLSDIR}/bin/lswsctrl stop  
        elif [ "${1}" = 'nginx' ]; then 
            PROC_NAME='nginx'
            silent service ${PROC_NAME} stop
        elif [ "${1}" = 'httpd' ]; then
            PROC_NAME='httpd'
            silent systemctl stop ${PROC_NAME}
        elif [ "${1}" = 'apache2' ]; then
            PROC_NAME='apache2' 
            silent systemctl stop ${PROC_NAME}
        elif [ "${1}" = 'h2o' ]; then
            PROC_NAME='h2o' 
            silent systemctl stop ${PROC_NAME}
        fi
        sleep 5
        if [ $(systemctl is-active ${PROC_NAME}) != 'active' ]; then 
            echoG "[OK] Stop ${PROC_NAME} service"
        else 
            echoR "[Failed] Stop ${PROC_NAME} service"
        fi 
    else 
        echoR '[ERROR] Failed to start the web server.'
        ps -ef | grep ${PROC_NAME} | grep -v grep
    fi 
}

rm_old_pkg(){
    silent systemctl stop ${1}
    if [ ${OSNAME} = 'centos' ]; then     
        silent yum remove ${1} -y 
    else 
        silent apt remove ${1} -y 
    fi 
    if [ $(systemctl is-active ${1}) != 'active' ]; then 
        echoG "[OK] remove ${1}"
    else 
        echoR "[Failed] remove ${1}"
    fi             
}

network_performance(){
    if [ -f /usr/sbin/sysctl ] || [ -f /sbin/sysctl ]; then
        echoG 'Setup NetWork Performance'
        silent sysctl -w net.core.netdev_max_backlog=4096
        silent sysctl -w net.core.somaxconn=4096
    else
        echoR 'System not support sysctl'    
    fi
}
ubuntu_pkg_basic(){
    echoG 'Install basic packages'
    if [ ! -e /bin/wget ]; then 
        silent apt-get install lsb-release -y
        silent apt-get install curl wget -y
    fi
    silent apt-get install curl net-tools software-properties-common -y
}

ubuntu_pkg_postfix(){
    if [ -e /usr/sbin/postfix ]; then 
        echoG 'Postfix already installed'
    else    
        echoG 'Installing postfix'
        DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' \
        -o Dpkg::Options::='--force-confold' install postfix >/dev/null 2>&1
        [[ -e /usr/sbin/postfix ]] && echoG 'Install postfix Success' || echoR 'Install postfix Failed'
    fi  
}

ubuntu_pkg_system(){
    if [ -e /usr/sbin/dmidecode ]; then
        echoG 'dmidecode already installed'
    else
        echoG 'Install dmidecode'
        silent apt-get install dmidecode -y
        [[ -e /usr/sbin/dmidecode ]] && echoG 'Install dmidecode Success' || echoR 'Install dmidecode Failed' 
    fi 
}

ubuntu_pkg_system(){
    if [ -e /usr/bin/iperf ]; then 
        echoG 'Iperf already installed'
    else    
        echoG 'Install Iperf'
        silent apt-get install iperf -y
        [[ -e /usr/bin/iperf ]] && echoG 'Install Iperf Success' || echoR 'Install Iperf Failed' 
    fi
    if [ -e /bin/netstat ]; then
        echoG 'netstat already installed'
    else
        echoG 'Install netstat'
        silent apt-get install net-tools -y
        [[ -e /bin/netstat ]] && echoG 'Install netstat Success' || echoR 'Install netstat Failed' 
    fi    
}

ubuntu_pkg_mariadb(){
    apt list --installed 2>/dev/null | grep mariadb-server-${MARIAVER} >/dev/null 2>&1
    if [ ${?} = 0 ]; then 
        echoG "Mariadb ${MARIAVER} already installed"
    else
        if [ -e /etc/mysql/mariadb.cnf ]; then 
            echoY 'Remove old mariadb'
            rm_old_pkg mariadb-server
        fi
        echoG "Install Mariadb ${MARIAVER}"
        silent apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
        silent add-apt-repository "deb [arch=amd64,arm64,ppc64el] http://mirror.lstn.net/mariadb/repo/${MARIAVER}/ubuntu bionic main"
        if [ "$(grep "mariadb.*${MARIAVER}" /etc/apt/sources.list)" = '' ]; then 
            echoR '[Failed] to add MariaDB repository'
        fi 
        silent apt update
        DEBIAN_FRONTEND=noninteractive apt -y -o Dpkg::Options::='--force-confdef' \
            -o Dpkg::Options::='--force-confold' install mariadb-server >/dev/null 2>&1        
    fi
    systemctl start mariadb
    local DBSTATUS=$(systemctl is-active mariadb)
    if [ ${DBSTATUS} = active ]; then 
        echoG "MARIADB is: ${DBSTATUS}"
    else 
        echoR "[Failed] Mariadb is: ${DBSTATUS}"
    fi    
}      


centos_pkg_basic(){
    echoG 'Install basic packages'
    if [ ! -e /bin/wget ]; then 
        silent yum install epel-release -y
        silent yum update -y
        silent yum install curl yum-utils wget -y
    fi
    if [[ -z "$(rpm -qa epel-release)" ]]; then
        silent yum install epel-release -y
    fi
    if [ ! -e /usr/bin/yum-config-manager ]; then 
        silent yum install yum-utils -y
    fi
    if [ ! -e /usr/bin/curl ]; then 
        silent yum install curl -y
    fi    
}

centos_pkg_postfix(){
    if [ -e /usr/sbin/postfix ]; then 
        echoG 'Postfix already installed'
    else    
        echoG 'Installing postfix'
        yum install postfix -y >/dev/null 2>&1
        [[ -e /usr/sbin/postfix ]] && echoG 'Install postfix Success' || echoR 'Install postfix Failed'
    fi    
}

centos_pkg_system(){
    if [ -e /usr/sbin/dmidecode ]; then
        echoG 'dmidecode already installed'
    else
        echoG 'Install dmidecode'
        silent yum install dmidecode -y
        [[ -e /usr/sbin/dmidecode ]] && echoG 'Install dmidecode Success' || echoR 'Install dmidecode Failed' 
    fi  
}

centos_pkg_network(){
    if [ -e /usr/bin/iperf ] || [ -e /usr/bin/iperf3 ]; then 
        echoG 'Iperf already installed'
    else    
        echoG 'Install Iperf'
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
    if [ -e /usr/bin/netstat ]; then
        echoG 'netstat already installed'
    else
        echoG 'Install netstat'
        silent yum install net-tools -y
        [[ -e /usr/bin/netstat ]] && echoG 'Install netstat Success' || echoR 'Install netstat Failed' 
    fi         
}    

centos_pkg_mariadb(){
    silent rpm -qa | grep mariadb-server-${MARIAVER}
    if [ ${?} = 0 ]; then 
        echoG "Mariadb ${MARIAVER} already installed"
    else
        if [ -e /etc/mysql/mariadb.cnf ]; then 
            echoY 'Remove old mariadb'
            rm_old_pkg mariadb-server
        fi
        echoG "InstallMariadb ${MARIAVER}"
        if [ "${OSTYPE}" != "x86_64" ] ; then
            CENTOSVER=centos${OSVER}-x86
        else
            CENTOSVER=centos${OSVER}-amd64
        fi        
        cat > ${REPOPATH}/MariaDB.repo << EOM
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/${MARIAVER}/${CENTOSVER}
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOM
        if [ "${OSNAMEVER}" = "CENTOS8" ] ; then
            silent yum install -y boost-program-options
            silent yum --disablerepo=AppStream install -y MariaDB-server MariaDB-client
        else
            silent yum install MariaDB-server MariaDB-client -y
        fi
    fi
    systemctl start mariadb
    local DBSTATUS=$(systemctl is-active mariadb)
    if [ ${DBSTATUS} = active ]; then 
        echoG "MARIADB is: ${DBSTATUS}"
    else 
        echoR "[Failed] Mariadb is: ${DBSTATUS}"
        echoR "You may want to manually run the command 'yum -y install MariaDB-server MariaDB-client' to check. Aborting installation!"
        exit 1        
    fi    
}    


set_mariadb_root(){
    SQLVER=$(mysql -u root -e 'status' | grep 'Server version')
    SQLVER_1=$(echo ${SQLVER} | awk '{print substr ($3,1,2)}')
    SQLVER_2=$(echo ${SQLVER} | awk -F '.' '{print $2}')
    mysql -u root -e "UPDATE mysql.user SET authentication_string = '' WHERE user = 'root';"
    mysql -u root -e "UPDATE mysql.user SET plugin = '' WHERE user = 'root';"
    if [ "${SQLVER_1}" -le "10" ] && [ "${SQLVER_2}" -le "2" ]; then
        mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASS}');"
    else
        mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';"
    fi
}

ubuntu_install_apache(){
    echoG 'Install Apache Web Server'
    if [ -e /usr/sbin/${APACHENAME} ]; then 
        echoY "Remove existing ${APACHENAME}" 
        rm_old_pkg ${APACHENAME}  
    fi    
    yes "" | add-apt-repository ppa:ondrej/apache2 >/dev/null 2>&1
    if [ "$(grep -iR apache2 ${REPOPATH}/)" = '' ]; then 
        echoR '[Failed] to add APACHE2 repository'
    fi     
    silent apt-get update
    apt install ${APACHENAME} -y >/dev/null 2>&1
    systemctl start ${APACHENAME} >/dev/null 2>&1
    SERVERV=$(echo $(apache2 -v | grep version) | awk '{print substr ($3,8,9)}')
    checkweb ${APACHENAME}
    echoG "Version: apache ${SERVERV}"
    echo "Version: apache ${SERVERV}" >>${SERVERACCESS} 
}

centos_install_apache(){
    echoG 'Install Apache Web Server'
    if [ -e /usr/sbin/${APACHENAME} ]; then 
        echoY "Remove existing ${APACHENAME}" 
        rm_old_pkg ${APACHENAME}
        silent yum remove httpd* -y
        KILL_PROCESS ${APACHENAME}  
    fi    
    cd ${REPOPATH}
    if [ "${OSNAMEVER}" != "CENTOS8" ] ; then
        wget https://repo.codeit.guru/codeit.el`rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release)`.repo >/dev/null 2>&1 
    fi    
    silent yum install ${APACHENAME} mod_ssl -y # mod_fcgi
    sleep 1
    silent systemctl start ${APACHENAME}
    SERVERV=$(echo $(httpd -v | grep version) | awk '{print substr ($3,8,9)}')
    #/usr/bin/yum-config-manager --disable codeit >/dev/null 2>&1
    checkweb ${APACHENAME}
    echoG "Version: apache ${SERVERV}"
    echo "Version: apache ${SERVERV}" >> ${SERVERACCESS}
}

### Install LSWS
install_lsws(){
    cd ${CMDFD}/
    if [ -e ${CMDFD}/lsws* ] || [ -d ${LSDIR} ]; then
        echoY 'Remove existing LSWS'
        silent systemctl stop lsws
        KILL_PROCESS litespeed
        rm -rf ${CMDFD}/lsws*
        rm -rf ${LSDIR}
    fi
    echoG 'Download LiteSpeed Web Server'
    wget -q https://www.litespeedtech.com/packages/5.0/lsws-5.4-ent-x86_64-linux.tar.gz -P ${CMDFD}/
    silent tar -zxvf lsws-*-ent-x86_64-linux.tar.gz
    rm -f lsws-*.tar.gz
    cd lsws-*
    wget -q http://license.litespeedtech.com/reseller/trial.key
    sed -i '/^license$/d' install.sh
    sed -i 's/read TMPS/TMPS=0/g' install.sh
    sed -i 's/read TMP_YN/TMP_YN=N/g' install.sh
    sed -i '/read [A-Z]/d' functions.sh
    sed -i 's|DEST_RECOM="/usr/local/lsws"|DEST_RECOM="/usr/local/entlsws"|g' functions.sh
    sed -i 's/HTTP_PORT=$TMP_PORT/HTTP_PORT=443/g' functions.sh
    sed -i 's/ADMIN_PORT=$TMP_PORT/ADMIN_PORT=7080/g' functions.sh
    sed -i "/^license()/i\
    PASS_ONE=${ADMIN_PASS}\
    PASS_TWO=${ADMIN_PASS}\
    TMP_USER=${USER}\
    TMP_GROUP=${GROUP}\
    TMP_PORT=''\
    TMP_DEST=''\
    ADMIN_USER=''\
    ADMIN_EMAIL=''
    " functions.sh

    echoG 'Install LiteSpeed Web Server'
    silent /bin/bash install.sh
    echoG 'Upgrade to Latest stable release'
    silent ${LSDIR}/admin/misc/lsup.sh -f
    silent ${LSDIR}/bin/lswsctrl start
    checkweb lsws
    SERVERV=$(cat /usr/local/entlsws/VERSION)
    echoG "Version: lsws ${SERVERV}"
    echo "Version: lsws ${SERVERV}" >> ${SERVERACCESS} 
    rm -rf ${CMDFD}/lsws-*
    cd /
}

ubuntu_install_lsws(){
    install_lsws
}

centos_install_lsws(){
    install_lsws
}

ubuntu_install_ols(){
    echoG 'Install openLiteSpeed Web Server'
    ubuntu_reinstall 'openlitespeed'
    wget -q -O - http://rpms.litespeedtech.com/debian/enable_lst_debian_repo.sh | bash >/dev/null 2>&1
    /usr/bin/apt ${OPTIONAL} install openlitespeed -y >/dev/null 2>&1
    ENCRYPT_PASS=$(${OLSDIR}/admin/fcgi-bin/admin_php* -q ${OLSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
    echo "admin:${ENCRYPT_PASS}" > ${OLSDIR}/admin/conf/htpasswd
    SERVERV=$(cat ${OLSDIR}/VERSION)
    echoG "Version: openlitespeed ${SERVERV}"
    echo "Version: openlitespeed ${SERVERV}" >> ${SERVERACCESS}     
    checkweb ols
}

centos_install_ols(){
    echoG 'Install openLiteSpeed Web Server'
    centos_reinstall 'openlitespeed'
    silent rpm -Uvh http://rpms.litespeedtech.com/centos/litespeed-repo-1.1-1.el7.noarch.rpm
    silent /usr/bin/yum ${OPTIONAL} openlitespeed -y
    ENCRYPT_PASS=$(${OLSDIR}/admin/fcgi-bin/admin_php* -q ${OLSDIR}/admin/misc/htpasswd.php ${ADMIN_PASS})
    echo "admin:${ENCRYPT_PASS}" > ${OLSDIR}/admin/conf/htpasswd
    SERVERV=$(cat ${OLSDIR}/VERSION)
    echoG "Version: openlitespeed ${SERVERV}"
    echo "Version: openlitespeed ${SERVERV}" >> ${SERVERACCESS}    
    checkweb ols
}

ubuntu_install_nginx(){
    echoG 'Install Nginx Web Server'
    if [ -e /usr/sbin/nginx ]; then 
        echoY "Remove existing nginx" 
        rm_old_pkg nginx 
        KILL_PROCESS nginx
    fi     
    echo "deb http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" \
        | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
    curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo apt-key add - >/dev/null 2>&1
    apt-get update >/dev/null 2>&1
    apt install nginx -y >/dev/null 2>&1
    systemctl start nginx
    SERVERV=$(echo $(/usr/sbin/nginx -v 2>&1) 2>&1)
    SERVERV=$(echo ${SERVERV} | grep -o '[0-9.]*')
    echoG "Version: nginx ${SERVERV}" 
    echo  "Version: nginx ${SERVERV}" >> ${SERVERACCESS} 
    checkweb nginx
}

centos_install_nginx(){
    echoG 'Install Nginx Web Server'
    if [ -e /usr/sbin/nginx ]; then 
        echoY "Remove existing nginx" 
        rm_old_pkg nginx 
        KILL_PROCESS nginx
    fi     
    cat > ${REPOPATH}/nginx.repo << EOM
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=0
enabled=1   
EOM
    silent yum install nginx -y
    systemctl start nginx
    SERVERV=$(echo $(/usr/sbin/nginx -v 2>&1) 2>&1)
    SERVERV=$(echo ${SERVERV} | grep -o '[0-9.]*$')
    echoG "Version: nginx ${SERVERV}" 
    echo "Version: nginx ${SERVERV}" >> ${SERVERACCESS} 
    checkweb nginx
}

ubuntu_install_h2o() {
    if [ -e /usr/bin/h2o ]; then 
        echo 'h2o already exist, skip!'
    else    
        echoG 'Install h2o Web Server'
        silent apt install h2o -y >/dev/null 2>&1
        SERVERV=$(/usr/bin/h2o --version | grep -o 'version [0-9.]*' | grep -o '[0-9.]*')
        echoG "Version: h2o ${SERVERV}"
        echo "Version: h2o ${SERVERV}" >> ${SERVERACCESS}
        checkweb h2o
    fi
}

centos_install_h2o() {
    ### Not support for test yet if openssl version < 1.1.0
    if [ -e /usr/sbin/h2o ]; then 
        echo 'h2o already exist, skip!'
    else      
        echoG 'Install h2o Web Server'
        cat > ${REPOPATH}/bintray-h2o-rpm.repo << EOM
[bintray-h2o-rpm]
name=bintray-h2o-rpm
baseurl=https://dl.bintray.com/tatsushid/h2o-rpm/centos/\$releasever/\$basearch/
gpgcheck=0
repo_gpgcheck=0
enabled=1
EOM
        silent yum install h2o -y
        SERVERV=$(/usr/sbin/h2o --version | grep -o 'version [0-9.]*' | grep -o '[0-9.]*')
        echoG "Version: h2o ${SERVERV}"
        echo "Version: h2o ${SERVERV}" >> ${SERVERACCESS}
    fi
}

ubuntu_install_caddy(){
    if [ -e /usr/local/bin/caddy ]; then 
        echo 'Caddy already exist, skip!'
    else
        echoG 'Install caddy Web Server'
        curl -s https://getcaddy.com | bash -s personal > /dev/null 2>&1
        SERVERV=$(caddy -version | awk '{print substr ($2,2)}')
        echoG "Version: caddy ${SERVERV}" 
        echo "Version: caddy ${SERVERV}" >> ${SERVERACCESS}    
    fi    
}

centos_install_caddy(){
    if [ -e /usr/bin/caddy ]; then 
        echo 'Caddy already exist, skip!'
    else    
        echoG 'Install caddy Web Server'
        yum install caddy -y > /dev/null 2>&1
        SERVERV=$(caddy -version | awk '{print $2}')
        echoG "Version: caddy ${SERVERV}" 
        echo "Version: caddy ${SERVERV}" >> ${SERVERACCESS}  
    fi   
}

ubuntu_reinstall(){
    apt --installed list 2>/dev/null | grep ${1} >/dev/null
    if [ ${?} = 0 ]; then
        OPTIONAL='--reinstall'
    else
        OPTIONAL=''
    fi  
}

centos_reinstall(){
    rpm -qa | grep ${1} >/dev/null
    if [ ${?} = 0 ]; then
        OPTIONAL='reinstall'
    else
        OPTIONAL='install'
    fi  
}
### Install PHP and Modules
ubuntu_install_php(){
    echoG 'Install PHP & Packages for LSWS'  
    ubuntu_reinstall "lsphp${PHP_P}${PHP_S}"    
    wget -qO - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash >/dev/null 2>&1
    for PKG in '' -common -curl -json -modules-source -mysql -opcache -pspell -recode -sybase -tidy; do
        /usr/bin/apt ${OPTIONAL} install -y lsphp${PHP_P}${PHP_S}${PKG} >/dev/null 2>&1
    done
    
    echoG 'Install PHP & Packages for Apache & Nginx'  
    ubuntu_reinstall "php${PHP_P}.${PHP_S}"
    for PKG in '' -bcmath -cli -common -curl -enchant -fpm -gd -gmp -json -mbstring -mysql -opcache \
        -pspell -readline -recode -soap -tidy -xml -xmlrpc -zip; do 
        /usr/bin/apt ${OPTIONAL} install -y php${PHP_P}.${PHP_S}${PKG} >/dev/null 2>&1
    done
    sed -i -e 's/extension=pdo_dblib.so/;extension=pdo_dblib.so/' \
        /usr/local/lsws/lsphp${PHP_P}${PHP_S}/etc/php/${PHP_P}.${PHP_S}/mods-available/pdo_dblib.ini
    sed -i -e 's/extension=shmop.so/;extension=shmop.so/' /etc/php/${PHP_P}.${PHP_S}/fpm/conf.d/20-shmop.ini
    sed -i -e 's/extension=wddx.so/;extension=wddx.so/' /etc/php/${PHP_P}.${PHP_S}/fpm/conf.d/20-wddx.ini
    NEWKEY='listen.backlog = 4096'
    line_change 'listen.backlog' ${FPMCONF} "${NEWKEY}"
    #TODO: FETCH SAME PHP INI
}

centos_install_php(){
    echoG 'Install PHP & Packages'  
    /usr/bin/yum install -y http://rpms.remirepo.net/enterprise/remi-release-${OSVER}.rpm >/dev/null 2>&1
    /usr/bin/yum install -y yum-utils >/dev/null 2>&1
    /usr/bin/yum-config-manager --enable remi-php${PHP_P}${PHP_S} >/dev/null 2>&1
    for PKG in '' -common -pdo -gd -mbstring -mysqlnd -litespeed -opcache -pecl-zip -tidy -gmp -bcmath \
        -enchant -cli -json -xml -fpm -recode -soap -xmlrpc -sodium; do 
        /usr/bin/yum install php${PKG} -y >/dev/null 2>&1
    done
    sed -i -e 's/extension=bz2/;extension=bz2/' /etc/php.d/20-bz2.ini
    sed -i -e 's/extension=pdo_sqlite/;extension=pdo_sqlite/' /etc/php.d/30-pdo_sqlite.ini
    #sed -i -e 's/extension=shmop/;extension=shmop/' /etc/php.d/20-shmop.ini
    sed -i -e 's/extension=sqlite3/;extension=sqlite3/' /etc/php.d/20-sqlite3.ini
    sed -i -e 's/extension=wddx/;extension=wddx/' /etc/php.d/30-wddx.ini  
    
    mkdir -p /var/run/php/
    NEWKEY="listen = /var/run/php/php${PHP_P}.${PHP_S}-fpm.sock"
    line_change 'listen = ' ${FPMCONF} "${NEWKEY}"    
    NEWKEY="listen.owner = ${USER}"
    line_change 'listen.owner = ' ${FPMCONF} "${NEWKEY}"
    NEWKEY="listen.group = ${GROUP}"
    line_change 'listen.group = ' ${FPMCONF} "${NEWKEY}"
    NEWKEY='listen.mode = 0660'
    line_change 'listen.mode = ' ${FPMCONF} "${NEWKEY}"  
    NEWKEY='listen.backlog = 4096'
    line_change 'listen.backlog' ${FPMCONF} "${NEWKEY}" 
    #TODO: FETCH SAME PHP INI       
}    

install_target(){
### Install WordPress + Cache
    ### WP CLI
    if [ -e /usr/local/bin/wp ]; then 
        echoG 'WP CLI already exist'
    else    
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        silent php wp-cli.phar --info --allow-root
        if [ ${?} != 0 ]; then
            echoR 'Issue with wp-cli.phar, Please check PHP!'
        else  
            mv wp-cli.phar /usr/local/bin/wp
        fi
    fi
    ######Mariadb
    silent mysql -u root -e 'status'
    if [ ${?} = 0 ]; then
        set_mariadb_root
        for SERVER in ${SERVER_LIST}; do
            WP_NAME=${WEB_ARR["${SERVER}"]}
            if [ -e ${DOCROOT}/${WP_NAME}/wp-config.php ]; then 
                echoG 'WordPress already exist'
            else       
                echoG "Install Target: /${WP_NAME}"
                mkdir ${DOCROOT}/${WP_NAME}
                cd ${DOCROOT}/${WP_NAME}
                silent wp core download --allow-root
                    #-e "update mysql.user set authentication_string=password('${MYSQL_ROOT_PASS}') where user='root';"
                ### Update user password
                mysql -u root -p${MYSQL_ROOT_PASS} << EOC
CREATE DATABASE ${WP_NAME};
grant all privileges on ${WP_NAME}.* to 'wordpress'@'localhost' identified by '${MYSQL_USER_PASS}';
EOC
                echoG 'Install WordPress via CLI'
                wp core config \
                    --dbname=${WP_NAME} \
                    --dbuser=wordpress \
                    --dbpass=${MYSQL_USER_PASS} \
                    --dbhost=localhost --dbprefix=wp_ \
                    --allow-root \
                    --quiet
                wp core install \
                    --url="${WP_DOMAIN_NAME}" \
                    --title="HTTP2Benchmark" \
                    --admin_user="admin" \
                    --admin_password=${ADMIN_PASS} \
                    --admin_email="email@domain.com" \
                    --allow-root \
                    --quiet      

                if [ "${SERVER}" = 'apache' ] || [ "${SERVER}" = 'caddy' ] || [ "${SERVER}" = 'h2o' ]; then
                    wp plugin install w3-total-cache \
                        --allow-root \
                        --activate \
                        --quiet
                    wp w3-total-cache import ${SCRIPTPATH}/../../webservers/apache/w3cache.json \
                        --allow-root \
                        > /dev/null 2>&1
                elif [ "${SERVER}" = 'lsws' ] || [ "${SERVER}" = 'openlitespeed' ]; then
                    wp plugin install litespeed-cache \
                        --allow-root \
                        --activate \
                        --quiet
                fi    
            fi   
        done
        systemctl restart mariadb
    else
        echo "mysql access deny, skip SQL root & wordpress setup!"
    fi
    mkdir -p ${CUSTOM_WP}
    cd ${SCRIPTPATH}/
### Install 1kb static file
    if [ ! -e ${DOCROOT}/1kstatic.html ]; then
        echoG 'Install Target: /1kstatic.html'
        cp ../../tools/target/1kstatic.html ${DOCROOT}
    else
        echoG '1kstatic.html already exist'       
    fi    
### Install 10kb static file
    if [ ! -e ${DOCROOT}/10kstatic.html ]; then
        echoG 'Install Target: /10kstatic.html'
        cp ../../tools/target/10kstatic.html ${DOCROOT}
    else
        echoG '10kstatic.html already exist'     
    fi    
### Install 100kb static file
    if [ ! -e ${DOCROOT}/100kstatic.html ]; then
        echoG 'Install Target: /100kstatic.html'
        silent dd if=/dev/zero of=${DOCROOT}/100kstatic.html bs=1K count=100
    else
        echoG '100kstatic.jpg already exist'    
    fi
### Install 1kb non gzip static file
    if [ ! -e ${DOCROOT}/1kstatic.jpg ]; then
        echoG 'Install Target: /1knogzip.jpg'
        silent dd if=/dev/zero of=${DOCROOT}/1knogzip.jpg bs=1K count=1 
    else
        echoG '1kstatic.jpg already exist'    
    fi 
### Install phpinfo page
    if [ ! -e ${DOCROOT}/phpinfo.php ]; then
        cat > ${DOCROOT}/phpinfo.php << EOC
<?php
    echo phpinfo();
?>
EOC
    else
        echoG 'phpinfo.php already exist' 
    fi

    rm -f ${DOCROOT}/index.html
    change_owner ${DOCROOT}
}

gen_selfsigned_cert(){
    KEYNAME="${CERTDIR}/http2benchmark.key"
    CERTNAME="${CERTDIR}/http2benchmark.crt"
    ### -nodes    = skip the option to secure our certificate with a passphrase.
    ### req -x509 = The "X.509" is a public key infrastructure standard
    ### -days 365 = The certificate will be considered valid for 1 Y
    ### rsa:2048  = make an RSA key that is 2048 bits long
    #silent openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${KEYNAME} -out ${CERTNAME} <<csrconf

    ### ECDSA 256bit
    openssl ecparam  -genkey -name prime256v1 -out ${KEYNAME}
    silent openssl req -x509 -nodes -days 365 -new -key ${KEYNAME} -out ${CERTNAME} <<csrconf
US
NJ
Virtual
HTTP2benchmark
Testing
webadmin
.
.
.
csrconf
}

check_spec(){
    echo -n 'Test Server - Memory Size: '                             | tee -a ${ENVLOG}
    echoY $(awk '$1 == "MemTotal:" {print $2/1024 "MB"}' /proc/meminfo) | tee -a ${ENVLOG}
    echo -n 'Test Server - CPU number: '                              | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^CPU(s):' | awk '{print $NF}')                | tee -a ${ENVLOG}
    echo -n 'Test Server - CPU Thread: '                              | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^Thread(s) per core' | awk '{print $NF}')     | tee -a ${ENVLOG}
    CPUNUM=$(nproc)
}

setup_process(){
    check_spec
    if [[ ${CPUNUM} > 1 ]]; then
        cd ${SCRIPTPATH}/
        ### Apache
        ### LSWS
        sed -i 's/<binding>1<\/binding>/<binding><\/binding>/g' ${LSDIR}/conf/httpd_config.xml
        sed -i 's/<reusePort>0<\/reusePort>/<reusePort>1<\/reusePort>/g' ${LSDIR}/conf/httpd_config.xml
        ### Nginx workers      
        sed -i 's/worker_processes  1;/worker_processes  2;/g' ${NGDIR}/nginx.conf
        ### OLS
        sed -i 's/binding                 1/binding                 3/g' "${OLSDIR}/conf/httpd_config.conf"          
    fi
}

ubuntu_setup_process(){
    setup_process
}

centos_setup_process(){
    setup_process
}

change_owner(){
    chown -R ${USER}:${GROUP} ${1}
}

ubuntu_setup_apache(){
    echoG 'Setting Apache Config'
    cd ${SCRIPTPATH}/
    a2enmod proxy_fcgi >/dev/null 2>&1
    a2enconf php${PHP_P}.${PHP_S}-fpm >/dev/null 2>&1
    a2enmod mpm_event >/dev/null 2>&1
    a2enmod ssl >/dev/null 2>&1
    a2enmod http2 >/dev/null 2>&1
    a2disconf other-vhosts-access-log >/dev/null 2>&1
    cp ../../webservers/apache/conf/deflate.conf ${APADIR}/mods-available
    cp ../../webservers/apache/conf/default-ssl.conf ${APADIR}/sites-available
    if [ ! -e ${APADIR}/sites-enabled/000-default-ssl.conf ]; then
        ln -s ${APADIR}/sites-available/default-ssl.conf ${APADIR}/sites-enabled/000-default-ssl.conf
    fi
    if [ ! -e ${APADIR}/conf-enabled/php${PHP_P}.${PHP_S}-fpm.conf ]; then 
        ln -s ${APADIR}/conf-available/php${PHP_P}.${PHP_S}-fpm.conf ${APADIR}/conf-enabled/php${PHP_P}.${PHP_S}-fpm.conf 
    fi    
    sed -i '/ CustomLog/s/^/#/' ${APADIR}/sites-enabled/000-default.conf                                                                           
}

centos_setup_apache(){
    echoG 'Setting Apache Config'
    cd ${SCRIPTPATH}/
    echo "Protocols h2 http/1.1" >> /etc/httpd/conf/httpd.conf
    sed -i '/logs\/access_log" common/s/^/#/' /etc/httpd/conf/httpd.conf
    sed -i '/LoadModule mpm_prefork_module/s/^/#/g' /etc/httpd/conf.modules.d/00-mpm.conf
    sed -i '/LoadModule mpm_event_module/s/^#//g' /etc/httpd/conf.modules.d/00-mpm.conf
    sed -i "s+SetHandler application/x-httpd-php+SetHandler proxy:unix:/var/run/php/php${PHP_P}.${PHP_S}-fpm.sock|fcgi://localhost+g" \
        /etc/httpd/conf.d/php.conf
    cp ../../webservers/apache/conf/deflate.conf ${APADIR}/conf.d
    cp ../../webservers/apache/conf/default-ssl.conf ${APADIR}/conf.d
    sed -i '/ErrorLog/s/^/#/g' /etc/httpd/conf.d/default-ssl.conf
    service httpd restart
}
ubuntu_setup_lsws(){
    echoG 'Setting LSWS Config'
    cd ${SCRIPTPATH}/
    backup_old ${LSDIR}/conf/httpd_config.xml
    backup_old ${LSDIR}/DEFAULT/conf/vhconf.xml
    cp ../../webservers/lsws/conf/httpd_config.xml ${LSDIR}/conf/
    cp ../../webservers/lsws/conf/vhconf.xml ${LSDIR}/DEFAULT/conf/
    mkdir -p ${LSDIR}/WORDPRESS/conf
    backup_old ${LSDIR}/WORDPRESS/conf/wordpress.xml
    cp ../../webservers/lsws/conf/wordpress.xml ${LSDIR}/WORDPRESS/conf/
    chown -R lsadm:lsadm ${LSDIR}/WORDPRESS/conf
} 

centos_setup_lsws(){
    echoG 'Setting LSWS Config'
    cd ${SCRIPTPATH}/
    backup_old ${LSDIR}/conf/httpd_config.xml
    backup_old ${LSDIR}/DEFAULT/conf/vhconf.xml
    cp ../../webservers/lsws/conf/httpd_config.xml ${LSDIR}/conf/
    cp ../../webservers/lsws/conf/vhconf.xml ${LSDIR}/DEFAULT/conf/
    sed -i "s/www-data/${USER}/g" ${LSDIR}/conf/httpd_config.xml
    sed -i "s|/usr/local/lsws/lsphp${PHP_P}${PHP_S}/bin/lsphp|/usr/bin/lsphp|g" ${LSDIR}/conf/httpd_config.xml  
    mkdir -p ${LSDIR}/WORDPRESS/conf
    backup_old ${LSDIR}/WORDPRESS/conf/wordpress.xml
    cp ../../webservers/lsws/conf/wordpress.xml ${LSDIR}/WORDPRESS/conf/
    chown -R lsadm:lsadm ${LSDIR}/WORDPRESS/conf
} 

setup_nginx(){
    echoG 'Setting Nginx Config' 
    cd ${SCRIPTPATH}/
    backup_old ${NGDIR}/nginx.conf
    backup_old ${NGDIR}/conf.d/default.conf
    cp ../../webservers/nginx/conf/nginx.conf ${NGDIR}/
    cp ../../webservers/nginx/conf/default.conf ${NGDIR}/conf.d/
    sed -i "s/user apache/user ${USER}/g"  ${NGDIR}/nginx.conf
    backup_old ${NGDIR}/wordpress.conf
    cp ../../webservers/nginx/conf/wordpress.conf ${NGDIR}/conf.d/
}

ubuntu_setup_nginx(){
    setup_nginx
}
centos_setup_nginx(){
    setup_nginx
}

ubuntu_setup_ols(){
    echoG 'Setting OpenLiteSpeed Config'
    cd ${SCRIPTPATH}/
    mkdir -p ${OLSDIR}/conf/vhosts/Wordpress
    mkdir -p ${OLSDIR}/wordpress
    backup_old ${OLSDIR}/conf/httpd_config.conf
    backup_old ${OLSDIR}/Example/conf/vhconf.conf
    cp ../../webservers/openlitespeed/conf/httpd_config.conf ${OLSDIR}/conf/
    cp ../../webservers/openlitespeed/conf/vhconf.conf ${OLSDIR}/conf/vhosts/Example/
    cp ../../webservers/openlitespeed/conf/wordpress.conf ${OLSDIR}/conf/vhosts/Wordpress/
    chown -R lsadm:lsadm ${OLSDIR}/conf/vhosts/Wordpress
    change_owner ${OLSDIR}/cachedata
} 

centos_setup_ols(){
    echoG 'Setting OpenLiteSpeed Config'
    cd ${SCRIPTPATH}/
    mkdir -p ${OLSDIR}/conf/vhosts/Wordpress
    mkdir -p ${OLSDIR}/wordpress
    backup_old ${OLSDIR}/conf/httpd_config.conf
    backup_old ${OLSDIR}/Example/conf/vhconf.conf
    cp ../../webservers/openlitespeed/conf/httpd_config.conf ${OLSDIR}/conf/
    cp ../../webservers/openlitespeed/conf/vhconf.conf ${OLSDIR}/conf/vhosts/Example/
    cp ../../webservers/openlitespeed/conf/wordpress.conf ${OLSDIR}/conf/vhosts/Wordpress/
    sed -i "s/www-data/${USER}/g" ${OLSDIR}/conf/httpd_config.conf
    sed -i "s|/usr/local/lsws/lsphp${PHP_P}${PHP_S}/bin/lsphp|/usr/bin/lsphp|g" ${OLSDIR}/conf/httpd_config.conf
    chown -R lsadm:lsadm ${OLSDIR}/conf/vhosts/Wordpress
    change_owner ${OLSDIR}/cachedata
} 

ubuntu_setup_caddy(){  
    echoG 'Setting Caddy Config' 
    cd ${SCRIPTPATH}/
    CADDY_BIN='/usr/local/bin/caddy'
    setcap 'cap_net_bind_service=+ep' ${CADDY_BIN}
    mkdir -p ${CADDIR}
    backup_old ${CADDIR}/Caddyfile
    backup_old /etc/systemd/system/caddy.service
    cp ../../webservers/caddy/conf/Caddyfile ${CADDIR}/
    cp ../../webservers/caddy/conf/caddy.service /etc/systemd/system/
    sed -i "s/example.com/${DOMAIN_NAME}/g" ${CADDIR}/Caddyfile
    sed -i "s/www-data/${USER}/g" /etc/systemd/system/caddy.service
    sed -i "s|/usr/local/bin/caddy|${CADDY_BIN}|g" /etc/systemd/system/caddy.service
    change_owner ${CADDIR}
    systemctl daemon-reload    
}

centos_setup_caddy(){  
    echoG 'Setting Caddy Config' 
    cd ${SCRIPTPATH}/
    CADDY_BIN='/usr/bin/caddy'
    setcap 'cap_net_bind_service=+ep' ${CADDY_BIN}
    mkdir -p ${CADDIR}
    backup_old ${CADDIR}/Caddyfile
    backup_old /etc/systemd/system/caddy.service
    cp ../../webservers/caddy/conf/Caddyfile ${CADDIR}/
    cp ../../webservers/caddy/conf/caddy.service /etc/systemd/system/
    sed -i "s/example.com/${DOMAIN_NAME}/g" ${CADDIR}/Caddyfile
    sed -i "s/www-data/${USER}/g" /etc/systemd/system/caddy.service
    sed -i "s|/usr/local/bin/caddy|${CADDY_BIN}|g" /etc/systemd/system/caddy.service
    change_owner ${CADDIR}
    systemctl daemon-reload    
}

setup_h2o(){
    backup_old ${HTODIR}/h2o.conf
    cp ../../webservers/h2o/conf/h2o.conf ${HTODIR}/
    sed -i "s/www-data/${USER}/g"  ${HTODIR}/h2o.conf
}

ubuntu_setup_h2o(){
    setup_h2o
}

centos_setup_h2o(){
   setup_h2o 
}    

mvexscript(){
    cd ${SCRIPTPATH}/
    cp "${1}" "${2}"
    local FILENAME=$(echo "${1}" | awk -F '/' '{print $NF}')
    chmod +x ${CMDFD}/${FILENAME}
}

copy_tools(){
    mvexscript '../../tools/switch.sh' "${CMDFD}/"
    mvexscript '../../tools/monitor.sh' "${CMDFD}/"
    mvexscript '../../tools/customwp.sh' "${CMDFD}/"
}

prepare(){
    gen_pwd
    clean_log_fd
    create_log_fd
    gen_selfsigned_cert 
}

ubuntu_pkg_main(){
    ubuntu_pkg_basic
    ubuntu_pkg_postfix
    ubuntu_pkg_system
    ubuntu_pkg_mariadb
}

centos_pkg_main(){
    centos_pkg_basic
    centos_pkg_postfix
    centos_pkg_system
    centos_pkg_network
    centos_pkg_mariadb
}

ubuntu_install_main(){
    ubuntu_sysupdate
    ubuntu_pkg_main
    ubuntu_install_apache
    ubuntu_install_lsws
    ubuntu_install_nginx
    ubuntu_install_ols
    ubuntu_install_caddy
    ubuntu_install_h2o
    ubuntu_install_php
}

centos_install_main(){
    centos_sysupdate
    centos_pkg_main
    centos_install_apache
    centos_install_lsws
    centos_install_nginx
    centos_install_ols
    centos_install_caddy
    centos_install_h2o
    centos_install_php
}

ubuntu_setup_main(){
    ubuntu_setup_apache
    ubuntu_setup_lsws
    ubuntu_setup_nginx
    ubuntu_setup_ols
    ubuntu_setup_caddy
    ubuntu_setup_h2o   
    ubuntu_setup_process 
}    

centos_setup_main(){
    centos_setup_apache
    centos_setup_lsws
    centos_setup_nginx
    centos_setup_ols
    centos_setup_caddy
    centos_setup_h2o 
    centos_setup_process   
}  

main(){
    prepare   
    if [ ${OSNAME} = 'centos' ]; then 
        centos_install_main
        centos_setup_main
    else
        ubuntu_install_main
        ubuntu_setup_main
    fi
    network_performance
    install_target
    display_pwd
    copy_tools
}
main
