#!/bin/bash
# /********************************************************************
# HTTP2 Benchmark Monitor Script
# *********************************************************************/
CMDFD='/opt'
ENVFD="${CMDFD}/env"
SERVERACCESS="${ENVFD}/serveraccess.txt"
CPU_CHECK_INTERVAL='0.2'

update_web_version(){
    if [ "${1}" = 'apache' ]; then
        SERVERV="$(echo $(apache2 -v | grep version) | awk '{print substr ($3,8,9)}')"
    elif [ "${1}" = 'httpd' ]; then   
        SERVERV="$(echo $(httpd -v | grep version) | awk '{print substr ($3,8,9)}')"
    elif [ "${1}" = 'lsws' ]; then 
        SERVERV="$(cat /usr/local/entlsws/VERSION)"
    elif [ "${1}" = 'ols' ]; then 
        SERVERV="$(cat /usr/local/lsws/VERSION)"        
    elif [ "${1}" = 'nginx' ]; then 
        SERVERV=$(echo $(/usr/sbin/nginx -v 2>&1) 2>&1)
        SERVERV="$(echo ${SERVERV} | grep -o '[0-9.]*')"
    else
        SERVERV='N/A'    
    fi    
    FILEVERSION="$(grep ${1} ${2} | awk '{print $NF}')"
    if [ "${SERVERV}" != "${FILEVERSION}" ]; then
        echo "Update ${1} to new version ${SERVERV}"
        sed -i "/${FILEVERSION}/ { s/${FILEVERSION}/${SERVERV}/g; }" ${2}
    fi
}

check_cpu(){
    local PREV_TOTAL=0
    local PREV_IDLE=0
    local PREV_COUNT=0
    while true; do
        # Get the total CPU statistics, discarding the 'cpu ' prefix.
        CPU=($(sed -n 's/^cpu\s//p' /proc/stat))
        IDLE=${CPU[3]}
        # Calculate the total CPU time.
        TOTAL=0
        for VALUE in "${CPU[@]}"; do
            let "TOTAL=$TOTAL+$VALUE"
        done
        # Calculate the CPU usage since we last checked.
        let "DIFF_IDLE=$IDLE-$PREV_IDLE"
        let "DIFF_TOTAL=$TOTAL-$PREV_TOTAL"
        let "DIFF_USAGE=(1000*($DIFF_TOTAL-$DIFF_IDLE)/$DIFF_TOTAL+5)/10"
        if [[ ${PREV_COUNT} -ne 0 ]]; then
            if [[ ${PREV_COUNT} -eq 5 ]]; then
                break
            fi
            if [[ ${DIFF_USAGE} -ge 30 ]]; then
                ((PREV_COUNT--))
            fi
        fi
        PREV_TOTAL="$TOTAL"
        PREV_IDLE="$IDLE"
        ((PREV_COUNT++))
        sleep .1
    done
    ### echo in integer
    echo ${DIFF_USAGE%.*}
}

check_mem(){
    #RAM=$(free -m | awk 'NR==2{printf "%s/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
    RAM=$(free -m | awk 'NR==2{printf "%.2f\n", $3*100/$2 }')
    ### echo in integer
    echo ${RAM}
}
kill_process_cpu(){
    MONITOR_PID=$(ps aux | grep monitor.sh | grep -v grep | awk '{print $2}')
    TOP_PID=$(ps -ef | grep ${MONITOR_PID} | grep top | awk '{print $2}')
    kill -TERM ${TOP_PID}
}

check_process_cpu(){
    local PROCESS_NAME=''
    case ${1} in 
        lsws|ols)         PROCESS_NAME='litespeed';;
        apache|httpd) PROCESS_NAME='httpd';;
        nginx)        PROCESS_NAME='nginx';;
    esac

    top -bn100 -d0.5 -p `pgrep ${PROCESS_NAME} | tr '\n' , | sed 's/,$/\n/'` | grep -Ev "Tasks:|Swap:" >> ${2} 
}

case ${1} in 
    CPU | cpu) check_cpu ;;
    [Mm]*) check_mem     ;;
    process_cpu) check_process_cpu ${2} ${3};; 
    kill_process_cpu) kill_process_cpu;;
    update_web_version) update_web_version ${2} ${SERVERACCESS};;
    *) echo 'Not support' ;;
esac
