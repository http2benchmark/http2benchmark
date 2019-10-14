#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark switch Script
# *********************************************************************/
CMDFD='/opt'
LSDIR='/usr/local/entlsws'
OLSDIR='/usr/local/lsws'
NGDIR='/etc/nginx'
APADIR='/etc/apache2'
CADDIR='/etc/caddy'
HTODIR='/etc/h2o'
DOCROOT='/var/www/html'
SERVER_NAME=''
SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
declare -A WEB_ARR=( [apache]=wp_apache [lsws]=wp_lsws [nginx]=wp_nginx [openlitespeed]=wp_openlitespeed [caddy]=wp_caddy [h2o]=wp_h2o )

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
        APADIR='/etc/httpd'
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
    silent systemctl stop h2o
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

linechange(){
    MATCHNUM=$(grep -n "${1}" ${2} | cut -d: -f 1 | wc -l)
    while [ ${MATCHNUM} -ge 1 ]; do
        LINENUM=$(grep -n -m 1 "${1}" ${2} | cut -d: -f 1)
        if [ "$LINENUM" != '' ]; then
            sed -i "${LINENUM}d" ${2}
            sed -i "${LINENUM}i${3}" ${2}
        else
            break
        fi
        MATCHNUM=$((MATCHNUM-1))
    done
}

rdlastfield(){
    if [ -e "${2}" ]; then
        LASTFIELD=$(grep ${1} ${2} | awk '{print $NF}')
    else
        echoR "${2} not found"
    fi
}

clean_cache(){
    WP_NAME=${WEB_ARR["${1}"]}
    if [ -d ${DOCROOT}/${WP_NAME} ]; then
        cd ${DOCROOT}/${WP_NAME}/
        if [ "${1}" = 'apache' ]; then
            rm -rf wp-content/cache/page/*
            rm -rf wp-content/cache/page_enhanced/*
        elif [ "${1}" = 'caddy' ]; then
            rm -rf wp-content/cache/page/*
            rm -rf wp-content/cache/page_enhanced/*
        elif [ "${1}" = 'h2o' ]; then
            rm -rf wp-content/cache/page/*
            rm -rf wp-content/cache/page_enhanced/*
        elif [ "${1}" = 'lsws' ]; then
            rm -rf ${DOCROOT}/lscache/*
        elif [ "${1}" = 'nginx' ]; then
            rm -rf /var/run/nginx-fastcgi-cache/*  
        elif [ "${1}" = 'openlitespeed' ]; then
            rm -rf ${DOCROOT}/lscache/*   
        else
            echoY "No cache clean defined for ${1} !"        
        fi
    else
        echo "${DOCROOT}/${WP_NAME} non exist, skip cache clean!"    
    fi       
}

custom_wpdomain(){
    for SERVER in ${SERVER_LIST}; do
        server_switch ${SERVER}
        WP_NAME=${WEB_ARR["${SERVER}"]}
        if [ -d ${DOCROOT}/${WP_NAME} ]; then
            cd ${DOCROOT}/${WP_NAME}/
            echoG "Update domain ${1} for ${SERVER}"
            wp option update home "https://${1}" --allow-root --quiet
            wp option update siteurl "https://${1}" --allow-root --quiet
        else
            echoY "${DOCROOT}/${WP_NAME} non exist, skip custom wordpress domain!" 
        fi
        echoG 'Clean cache'
        clean_cache ${SERVER}
    done    
}

custom_domain(){
    for SERVER in ${SERVER_LIST}; do
        case ${SERVER} in 
            apache)
                NEWKEY="\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ ServerName ${2};"
                linechange "${1}" ${APADIR}/conf.d/default-ssl.conf "${NEWKEY}"               
            ;;
            nginx)
                NEWKEY="\ \ \ \ server_name  ${2};"
                linechange "${1}" ${NGDIR}/conf.d/wordpress.conf "${NEWKEY}"            
            ;;
            lsws)
                NEWKEY="\ \ \ \ \ \ \ \ \ \ <domain>${2}</domain>"
                linechange "${1}" ${LSDIR}/conf/httpd_config.xml "${NEWKEY}"
            ;;  
            openlitespeed)
                NEWKEY="\ \ map                     wordpress ${2}"
                linechange "${1}" ${OLSDIR}/conf/httpd_config.conf "${NEWKEY}"            
            ;; 
            caddy)
                NEWKEY="${2}:443 {"
                linechange "${1}" ${CADDIR}/Caddyfile "${NEWKEY}"            
            ;;
            h2o)
                NEWKEY=" \ \"${2}\":"
                linechange "${1}" ${HTODIR}/h2o.conf "${NEWKEY}"
            ;;
        esac
    done    
    custom_wpdomain ${2}
}


server_switch(){
    server_stop
    if [ ${OSNAME} = 'centos' ]; then
        if [ ! -f /var/run/php/ ]; then 
            mkdir -p /var/run/php/
        fi
    fi    
    if [[ ${1} =~ (ap|AP) ]] || [[ ${1} =~ (ht|HT) ]]; then
	    if [ ${OSNAME} = 'centos' ]; then 
            SERVER_NAME='php-fpm httpd'
        else 
            SERVER_NAME='php7.2-fpm apache2'
        fi
    elif [[ ${1} =~ ^(ls|LS) ]]; then
        SERVER_NAME='lsws'
    elif [[ ${1} =~ ^(ols|OLS|openlitespeed) ]]; then
        SERVER_NAME='openlitespeed'    
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
    elif [[ ${1} =~ ^(h2o|H2O) ]]; then
        if [ ${OSNAME} = 'centos' ]; then
            SERVER_NAME='php-fpm h2o'
        else    
            SERVER_NAME='php7.2-fpm h2o'
        fi            
    else 
    	echoR 'Please input apache, lsws, openlitespeed, caddy, h2o or nginx'
    fi	
    echoNG "Switching to ${SERVER_NAME}..  "
    if [ "${SERVER_NAME}" = 'lsws' ]; then 
        silent ${LSDIR}/bin/lswsctrl start; sleep 5
        ps aux | grep litespeed | grep -v grep >/dev/null 2>&1
        [[ ${?} = 0 ]] && STATUS='active' || STATUS='inactive'
    elif [ "${SERVER_NAME}" = 'openlitespeed' ]; then
        silent ${OLSDIR}/bin/lswsctrl start; sleep 5
        ps aux | grep openlitespeed | grep -v grep >/dev/null 2>&1
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
    apache | lsws | nginx | ols | openlitespeed | caddy | h2o) server_switch ${1} ;;
    custom_domain ) custom_domain ${2} ${3};;
    *) echo 'Please input apache, lsws, nginx, openlitespeed, caddy or h2o' ;;
esac    