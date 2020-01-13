#!/bin/bash
CMDFD='/opt/h2bench'
ENVFD="${CMDFD}/env"
CUSTOM_WP="${ENVFD}/custom_wp"
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
DOCROOT='/var/www/html'
declare -A WEB_ARR=( [apache]=wp_apache [lsws]=wp_lsws [nginx]=wp_nginx [openlitespeed]=wp_openlitespeed [caddy]=wp_caddy [h2o]=wp_h2o )
WPNUM=$(ls -l ${CUSTOM_WP}/*.tar.gz 2>/dev/null | wc -l)
SQLNUM=$(ls -l ${CUSTOM_WP}/*.sql 2>/dev/null | wc -l)
SERVERACCESS="${ENVFD}/serveraccess.txt"
DB_PWD=$(grep MYSQL_root_PASS ${ENVFD}/serveraccess.txt | awk '{print $2}')

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

backup_old(){
    if [ -f ${1} ] && [ ! -f ${1}_old ]; then
       mv ${1} ${1}_old
    fi
}

backup_to_tmp(){
    if [ -f ${1} ] && [ ! -f /tmp/${1}_old ]; then
       mv ${1} /tmp/${1}_old
    fi
}

ck_system(){
    if [ -f /etc/redhat-release ] ; then
        USER='apache'
        GROUP='apache'    
    else
        USER='www-data'
        GROUP='www-data'
    fi
}

ck_only_one(){
    if [ ${1} -eq 1 ]; then
        echoG "File number pass."
    elif [ ${1} -eq 0 ]; then
        echoR "File not exist!"
        exit 1
    elif [ ${1} -gt 1 ]; then 
        echoR "Too many files!"
        exit 1
    fi    
}

import_wp(){
    cd ${DOCROOT}/${WEB_ARR["${1}"]}
    backup_to_tmp wp-config.php; cd ${DOCROOT}
    rm -rf ${WEB_ARR["${1}"]}; mkdir ${WEB_ARR["${1}"]}; cd ${WEB_ARR["${1}"]}
    tar -zxf ${CUSTOM_WP}/*.tar.gz
    backup_old ${DOCROOT}/${WEB_ARR["${1}"]}/wp-config.php
    mv /tmp/wp-config.php_old wp-config.php
}

import_db(){
    mysql -u root -p${DB_PWD} ${WEB_ARR["${1}"]} < ${CUSTOM_WP}/*.sql
}

change_owner(){
    chown -R ${USER}:${GROUP} ${1}
}

main(){
    ck_system
    ck_only_one ${WPNUM}
    ck_only_one ${SQLNUM}
    for SERVER in ${SERVER_LIST}; do
        echoG "Importing for ${SERVER}"
        import_wp ${SERVER}
        import_db ${SERVER}
        change_owner ${DOCROOT}/${WEB_ARR["${SERVER}"]}
    done
}   
main
exit 0
