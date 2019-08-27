#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark switch Script
# *********************************************************************/
CMDFD='/opt'
LSDIR='/usr/local/entlsws'
OLSDIR='/usr/local/lsws'
DOCROOT='/var/www/html'
SERVER_NAME=''
SERVER_LIST="apache lsws nginx caddy"
declare -A WEB_ARR=( [apache]=wp_apache [lsws]=wp_lsws [nginx]=wp_nginx [caddy]=wp_caddy )

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

echoNG() {
    echo -ne "\033[38;5;71m${1}\033[39m"
}

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

checksystem(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        USER='apache'
        GROUP='apache'
        REPOPATH='/etc/yum.repos.d'
        APACHENAME='httpd'
    elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
        OSNAME=ubuntu 
        REPOPATH='/etc/apt/sources.list.d'
        APACHENAME='apache2'
    else 
        echoR 'Please use CentOS or Ubuntu OS'
    fi      
}
checksystem

server_stop()
{   
    #echoG 'Stopping web servers...'
    silent systemctl stop nginx 
    silent systemctl stop ${APACHENAME} 
    silent systemctl stop php7.2-fpm php-fpm
    silent systemctl stop caddy
    silent ${LSDIR}/bin/lswsctrl stop
    silent ${OLSDIR}/bin/lswsctrl stop
    WSWATCH=$(ps aux | grep '[w]swatch.sh' | awk '{print $2}')
    if [ "${WSWATCH}" != '' ]; then 
        kill -9 "${WSWATCH}"
    fi    

    sleep 5
    while :; do 
        PNUM=$(netstat -antpl | grep -v 'tcp6\|udp' | grep ':443.*LISTEN' | awk '{print $7}' | cut -d / -f 1)
        if [ "${PNUM}" = '' ]; then 
            #echoG 'Port 443 is not occupied'
            break
        else 
            echoY 'Port 443 is occupied, please wait..' 
            silent kill -9 ${PNUM}   
            sleep 5 
        fi    
    done     
}

clean_cache(){
    WP_NAME=${WEB_ARR["${1}"]}
    cd ${DOCROOT}/${WP_NAME}/
    if [ "${1}" = 'apache' ]; then
        wp w3-total-cache flush all \
            --allow-root \
            --quiet
    elif [ "${1}" = 'caddy' ]; then
        wp w3-total-cache flush all \
            --allow-root \
            --quiet            
    elif [ "${1}" = 'lsws' ]; then
        wp lscache-purge all \
            --allow-root \
            --quiet        
    elif [ "${1}" = 'nginx' ]; then
        rm -rf /var/run/nginx-fastcgi-cache/*
    fi    
}

custom_wpdomain(){
    for SERVER in ${SERVER_LIST}; do
        server_switch ${SERVER}
        WP_NAME=${WEB_ARR["${SERVER}"]}
        cd ${DOCROOT}/${WP_NAME}/
        echoG "Update domain ${1} for ${SERVER}"
        wp option update home "https://${1}/${WP_NAME}" \ 
            --allow-root \
            --quiet
        wp option update siteurl "https://${1}/${WP_NAME}" \
            --allow-root \
            --quiet
        echoG 'Clean cache'
        clean_cache ${SERVER}
    done    
}

server_switch(){
    server_stop
    
    if [[ ${1} =~ (ap|AP) ]] || [[ ${1} =~ (ht|HT) ]]; then
	    if [ ${OSNAME} = 'centos' ]; then 
            SERVER_NAME='php-fpm httpd'
        else 
            SERVER_NAME='php7.2-fpm apache2'
        fi
    elif [[ ${1} =~ ^(ls|LS) ]]; then
        SERVER_NAME='lsws'
    elif [[ ${1} =~ ^(ols|OLS) ]]; then
        SERVER_NAME='ols'    
    elif [[ ${1} =~ ^(ng|NG) ]]; then  
        if [ ${OSNAME} = 'centos' ]; then
            SERVER_NAME='php-fpm nginx'
        else    
            SERVER_NAME='php7.2-fpm nginx'
        fi    
    elif [[ ${1} =~ ^(caddy|CADDY) ]]; then
        if [ ${OSNAME} = 'centos' ]; then
            SERVER_NAME='php-fpm caddy'
        else    
            SERVER_NAME='php7.2-fpm caddy'
        fi      
    else 
    	echoR 'Please input apache, lsws, ols, caddy or nginx'
    fi	
    echoNG "Switching to ${SERVER_NAME}..  "
    if [ "${SERVER_NAME}" = 'lsws' ]; then 
        silent ${LSDIR}/bin/lswsctrl start; sleep 5
        ps aux | grep openlitespeed | grep -v grep >/dev/null 2>&1
        [[ ${?} = 0 ]] && STATUS='active' || STATUS='inactive'
    elif [ "${SERVER_NAME}" = 'ols' ]; then
        silent ${OLSDIR}/bin/lswsctrl start; sleep 5
        ps aux | grep litespeed | grep -v grep >/dev/null 2>&1
        [[ ${?} = 0 ]] && STATUS='active' || STATUS='inactive'
    else
        silent systemctl start ${SERVER_NAME}; sleep 5
        STATUS=$(systemctl is-active ${SERVER_NAME})
    fi         
    if [ "$(echo ${STATUS} | grep 'failed')" != 'failed' ] || [ "$(echo ${STATUS} | grep 'inactive')" != 'inactive' ]; then
        echoG "[OK] ${SERVER_NAME}"
    else
        echoR "[Failed] to start ${SERVER_NAME}"
    fi    
}

case ${1} in
    apache | lsws | nginx | ols | caddy) server_switch ${1} ;;
    custom_wpdomain ) custom_wpdomain ${2};;
    *) echo 'Please input apache, lsws, nginx, ols, caddy' ;;
esac    