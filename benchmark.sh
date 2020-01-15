#!/usr/bin/env bash
# /********************************************************************
# HTTP2 Benchmark Script
# *********************************************************************/

SERVER_LIST="lsws nginx"
#SERVER_LIST="apache lsws nginx openlitespeed caddy h2o"
TOOL_LIST="h2load wrk"
#TOOL_LIST="h2load wrk jmeter"
TARGET_LIST="1kstatic.html 1knogzip.jpg wordpress"
#TARGET_LIST="1kstatic.html 1knogzip.jpg 10kstatic.html 100kstatic.html wordpress"

CPU_THRESHOLD=30
### Add Interval to avoid potential traffic block
INTERVAL=0
CHECK='ON'
DATE=$(date +%m%d%y-%H%M%S)
CMDFD='/opt/h2bench'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
ENVLOG="${ENVFD}/client/environment.log"
CLIENTTOOL="${CMDFD}/tools"
CLIENTCF="${CLIENTTOOL}/config"
TEST_IP="${ENVFD}/ip.log"
CUSTOM_WP="${ENVFD}/custom_wp"
BENDATE="${CMDFD}/Benchmark/${DATE}"
TESTSERVERIP="$(cat ${TEST_IP})"
SSH=(ssh -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
JMFD='apache-jmeter'
JMPLAN='jmeter.jmx'
JMCFPATH="${CLIENTTOOL}/${JMFD}/bin/examples/${JMPLAN}"
RESULT_NAME='RESULTS'
FILE_CONTENT=""
LASTFIELD=''
KILL_PROCESS_LIST=''
TMP_TARGET=''
TARGET_DOMAIN=""
TARGET_WP_DOMAIN=""
HEADER='Accept-Encoding: gzip,deflate'
SERVER_VERSION='N/A'
ROUNDNUM=3
HOST_FILE="/etc/hosts"
DOMAIN_NAME='benchmark.com'
WP_DOMAIN_NAME='wordpress.benchmark.com'
declare -A PARAM_ARR
declare -A WEB_ARR=( [apache]=wp_apache/ [lsws]=wp_lsws/ [nginx]=wp_nginx/ [ols]=wp_openlitespeed/ [caddy]=wp_caddy/ [h2o]=wp_h2o/ )

CONCURRENT_STREAMS=$(grep '\-m' ${CLIENTCF}/h2load.conf  | awk '{print $NF}')

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
echoCYAN() {
    echo -e "\033[1;4;36m${1}\033[0m"
}

grep_1stcolumn2(){
    grep -m1 ${1} ${2} | awk -F '\"' '{print $2}'
}

help_message(){
    case ${1} in
        "1")
        echoCYAN "How to view the site from your browser?"
        echo "please add the following entries to your $(echoB "${HOST_FILE}") file: "
        echoG "$(cat ${TEST_IP}) ${DOMAIN_NAME}"
        echoG "$(cat ${TEST_IP}) ${WP_DOMAIN_NAME}"

        echoCYAN "How to customize the WordPress domain?"
        echo 'Run the following command to change the WordPress home URL and site URL: '
        echoG "${CLIENTTOOL}/custom.sh domain [example.com]"

        local SERVER_L=$(grep_1stcolumn2 '^SERVER_LIST' ${0})
        local SERVER_L_SUPPORT=$(grep_1stcolumn2 '#SERVER_LIST' ${0})
        local TOOL_L=$(grep_1stcolumn2 '^TOOL_LIST' ${0})
        local TOOL_L_SUPPORT=$(grep_1stcolumn2 '#TOOL_LIST' ${0})
        local TARGET_L=$(grep_1stcolumn2 '^TARGET_LIST' ${0})
        local TARGET_L_SUPPORT=$(grep_1stcolumn2 '#TARGET_LIST' ${0})       

        echoCYAN "How to change the testing servers: "
        echo -e 'Edit' $(echoB "${0} ")
        echo -e '#' $(echoY "Server List: ${SERVER_L}")
        echo -e '#' $(echoG "Support opt: ${SERVER_L_SUPPORT}")

        echoCYAN "How to change the testing tools: "
        echo -e 'Edit' $(echoB "${0} ")
        echo -e '#' $(echoY "Tools List : ${TOOL_L}")
        echo -e '#' $(echoG "Support opt: ${TOOL_L_SUPPORT}")

        echoCYAN "How to change the testing targets: "
        echo -e 'Edit' $(echoB "${0} ")
        echo -e '#' $(echoY "Target List: ${TARGET_L}")
        echo -e '#' $(echoG "Support opt: ${TARGET_L_SUPPORT}")

        echoCYAN "How to change the testing tool parameters: "
        echo -e "Edit $(echoB "${CLIENTCF}/h2load.conf ") for h2load"
        
        echoCYAN "How to import your wordpress site to testing?"
        echo -e 'Step 1. Compress site by running the following command from your WordPress folder: '
        echoG "tar -czvf [mysite.tar.gz] ."
        echo 'Step 2. Export wordpress database with the following command: '
        echoG "mysqldump -u root -p[ROOT_PASSWORD] [DB_NAME] > wordpressdb.sql"
        echo "Step 3. Upload 'mysite.tar.gz' and 'mywordpressdb.sql' to the test server folder:" $(echoB "${CUSTOM_WP}")
        echo "With any kind of file transfer tool you like. "
        echo "Step 4. Execute the auto wordpress migration. Run the following command: "
        echoG "bash ${CLIENTTOOL}/custom.sh wordpress"

        exit 0
        ;;
        "2")
        echoB "#############  Test Environment  #################"
        check_network ${TESTSERVERIP}
        check_spec ${TESTSERVERIP}
        "${SSH[@]}" root@${TESTSERVERIP} "${CMDFD}/monitor.sh check_server_spec"
        echoB "#############  Benchmark Result  #################"
        sort_log
        ;;
        "3")
        echoG "Benchmark will be pending when server load > ${CPU_THRESHOLD}"
        ;;
    esac
}

silent() {
  if [[ $debug ]] ; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

linechange(){
    LINENUM=$(grep -n "${1}" ${2} | cut -d: -f 1)
    if [ -n "$LINENUM" ] && [ "$LINENUM" -eq "$LINENUM" ] 2>/dev/null; then
        sed -i "${LINENUM}d" ${2}
        sed -i "${LINENUM}i${3}" ${2}
    fi
}

checkroundin(){
    if [ -z ${1} ]; then
        ROUNDNUM=3
    else
        if [ ${1} -lt 3 ]; then
            echoY "Suggest you to input value larger or equal to 3 next time"
            ROUNDNUM=${1}
        else
            ROUNDNUM=${1}
        fi
    fi
}

checksystem(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
        grep -i fedora /etc/redhat-release >/dev/null 2>&1
        if [ ${?} = 0 ]; then 
            OSVER=$(awk '{print $3}' /etc/redhat-release)
        else
            OSVER=$(awk '{print substr($4,0,1)}' /etc/redhat-release)
        fi  
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

create_log_fd(){
    for SERVER in ${SERVER_LIST}; do 
        mkdir -p "${BENDATE}/${SERVER}"
    done    
}

readwholefile(){
    if [ -e ${1} ]; then
        FILE_CONTENT=$(sed ':a;N;$!ba;s/\n/ /g' ${1} | tr -s ' ')
    else
        echoR "${1} not found"
    fi
}

rdlastfield(){
    if [ -e "${2}" ]; then
        LASTFIELD=$(grep ${1} ${2} | awk '{print $NF}')
    else
        echoR "${2} not found"
    fi
}

noext_target(){
    FILENAME=$(basename -- "${1}")
    FILENAME=${FILENAME%.*}
}

check_wp_target(){
    if [ "${1}" = 'wordpress' ]; then
        TMP_TARGET=''
        TMP_DOMAIN=${TARGET_WP_DOMAIN}
    else
        TMP_TARGET="${1}"
        TMP_DOMAIN=${TARGET_DOMAIN}
    fi
}

target_check(){
    check_wp_target ${2}
    if [ ! -z ${3} ]; then
        echo "Check Target command: curl -H 'User-Agent: benchmark' -H "${HEADER}" -sILk https://${1}/${TMP_TARGET}" >> ${3}
    fi
    echo 'Target Response >>>>>>>>>>>>>>>>>>>>>>' >> ${MAPPINGLOG}
    silent curl -H "User-Agent: benchmark" -H "${HEADER}" -siLk https://${1}/${TMP_TARGET}
    curl -H "User-Agent: benchmark" -H "${HEADER}" -sILk https://${1}/${TMP_TARGET} >> ${MAPPINGLOG}
    echo 'Target Response <<<<<<<<<<<<<<<<<<<<<<<' >> ${MAPPINGLOG}
}

get_server_version(){
    if [ -e ${BENDATE}/env/server/serveraccess.txt ]; then
        SERVER_VERSION=$(grep "Version.*${1}" ${BENDATE}/env/server/serveraccess.txt | awk '{print $3}')
    else
        SERVER_VERSION='N/A'
    fi
}

validate_tool(){
    echoG 'Checking benchmark Tools..'
    for TOOL in ${TOOL_LIST}; do
        if [ ${TOOL} = 'jmeter' ]; then
            cd ${CLIENTTOOL}/${JMFD}/bin
            JMTEST=$(./jmeter -v)
            if [ ${?} = 0 ]; then
                echoG '[OK] to run Jmeter'
                RUNJMETER='true'
            else
                echoR '[Failed] to run Jmeter, due to: '
                echoR "${JMTEST}"
                RUNJMETER='false'
            fi
        fi
        if [[ ${TOOL} == h2load* ]]; then
            silent h2load --version
            if [ ${?} = 0 ]; then
                echoG '[OK] to run h2load'
                RUNH2LOAD='true'
            else
                echoR '[Failed] to run h2load'
                RUNH2LOAD='false'
            fi
        fi
        if [ ${TOOL} = 'siege' ]; then
            silent siege -V
            if [ ${?} = 0 ]; then
                echoG '[OK] to run siege'
                RUNSIEGE='true'
            else
                echoR '[Failed] to run siege'
                RUNSIEGE='false'
            fi
        fi
        if [ ${TOOL} = 'wrk' ]; then
            ${CLIENTTOOL}/wrk/wrk -v | grep -i Copyright >/dev/null 2>&1
            if [ ${?} = 0 ]; then
                echoG '[OK] to run wrk'
                RUNWRK='true'
            else
                echoR '[Failed] to run wrk'
                RUNWRK='false'
            fi
        fi
    done
}

validate_server(){
    STATUS=$(curl -H "User-Agent: benchmark" -H "${HEADER}" -X GET -ILks -o /dev/null -w '%{http_code}' https://${1}/${2})
}

siege_benchmark(){
    check_wp_target ${2}
    echo "Target: https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    target_check ${1} ${2} ${MAPPINGLOG}
    echo "Benchmark Command: siege ${FILE_CONTENT} ${HEADER} https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    siege ${FILE_CONTENT} "${HEADER}" "https://${1}/${TMP_TARGET}" 1>/dev/null 2>> ${MAPPINGLOG}
}
h2load_benchmark(){
    check_wp_target ${2}
    echo "Target: https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    target_check ${1} ${2} ${MAPPINGLOG}
    echo "Benchmark Command: h2load ${FILE_CONTENT} ${HEADER} https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    h2load ${FILE_CONTENT} "${HEADER}" "https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
}
jmeter_benchmark(){
    check_wp_target ${2}
    cd ${CLIENTTOOL}/${JMFD}/bin
    echo "Target: https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    target_check ${1} ${2} ${MAPPINGLOG}
    NEWKEY="          <stringProp name="HTTPSampler.domain">${1}/${TMP_TARGET}</stringProp>"
    linechange 'HTTPSampler.domain' ${JMCFPATH} "${NEWKEY}"
    ./jmeter.sh ${FILE_CONTENT} "${JMFD}" >> ${MAPPINGLOG}
    cd ~
}
wrk_benchmark(){
    check_wp_target ${2}
    cd ${CLIENTTOOL}/wrk
    echo "Target: https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    target_check ${1} ${2} ${MAPPINGLOG}
    echo "Benchmark Command: wrk ${FILE_CONTENT} ${HEADER} https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
    ./wrk ${FILE_CONTENT} "${HEADER}" "https://${1}/${TMP_TARGET}" >> ${MAPPINGLOG}
}

server_switch(){
    "${SSH[@]}" root@${1} "${CMDFD}/switch.sh ${2}"
}

check_server_cpu(){
    TESTSERVERCPU=$("${SSH[@]}" root@${1} "${CMDFD}/monitor.sh ${2}")
}

check_process_cpu(){
    "${SSH[@]}" root@${1} "${CMDFD}/monitor.sh process_cpu ${2} ${3}" >/dev/null 2>&1 &
    KILL_PROCESS_LIST+=" $!"
}

kill_process_cpu(){
    "${SSH[@]}" root@${1} "${CMDFD}/monitor.sh kill_process_cpu" >/dev/null 2>&1
}

loop_check_server_cpu(){
    while :; do
        check_server_cpu ${TESTSERVERIP} CPU
        if [[ ${TESTSERVERCPU} -ge ${CPU_THRESHOLD} ]]; then
            echoY "Test server: CPU ${TESTSERVERCPU}% is high, please wait.."
            sleep 30
        else
            break
        fi
    done
}

check_network(){
    silent "${SSH[@]}" root@${1} "iperf -s >/dev/null 2>&1 &"
    silent "${SSH[@]}" root@${1} "ps aux | grep [i]perf"
    if [ ${?} = 0 ]; then
        iperf -c ${1} -i1  >> ${ENVLOG}
        sleep 1
        "${SSH[@]}" root@${1} "kill -9 \$(ps aux | grep '[i]perf -s' | awk '{print \$2}')"
        echo -n 'Network traffic: '
        echoG "$(awk 'END{print $7,$8}' ${ENVLOG})"
    else
        echoR '[Failed] to Iperf due to connection issue'    
    fi
    ping -c5 -w3 ${1} >> ${ENVLOG}
    echo -n 'Network latency: '
    echoG "$(awk -F '/' 'END{print $5}' ${ENVLOG}) ms"
}

check_spec(){
    echo -n 'Client Server - Memory Size: '                                  | tee -a ${ENVLOG}
    echoY $(awk '$1 == "MemTotal:" {print $2/1024 "MB"}' /proc/meminfo)      | tee -a ${ENVLOG}
    echo -n 'Client Server - CPU number: '                                   | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^CPU(s):' | awk '{print $NF}')                     | tee -a ${ENVLOG}
    echo -n 'Client Server - CPU Thread: '                                   | tee -a ${ENVLOG}
    echoY $(lscpu | grep '^Thread(s) per core' | awk '{print $NF}')          | tee -a ${ENVLOG}
    echo -n 'Client Server - CPU Model: '                                    | tee -a ${ENVLOG}
    echoY "$(lscpu | grep '^Model name' | awk -F ':' '{print $2}'|tr -s ' ')"| tee -a ${ENVLOG}
}

before_test(){
    if [ -s ${ENVLOG} ]; then
        rm -f ${ENVLOG}; touch ${ENVLOG}
    fi
    validate_tool
    sleep ${INTERVAL}
    kill_process_cpu ${TESTSERVERIP}
}

load_param(){
    if [ -f "${CLIENTCF}/$1_$2.conf" ]; then
        readwholefile "${CLIENTCF}/$1_$2.conf"
    else
	readwholefile "${CLIENTCF}/$1.conf"
    fi
    PARAM_ARR["$1_$2"]="${FILE_CONTENT} '${HEADER}'"
}

main_test(){
    START_TIME="$(date -u +%s)"
    before_test
    for SERVER in ${SERVER_LIST}; do
        sleep ${INTERVAL}
        server_switch ${TESTSERVERIP} ${SERVER}
        get_server_version ${SERVER}
        rdlastfield ${SERVER} "${CLIENTCF}/urls.conf"
        TARGET_DOMAIN="${LASTFIELD}"
        rdlastfield ${SERVER} "${CLIENTCF}/urls-wp.conf"
        TARGET_WP_DOMAIN="${LASTFIELD}"        
        echoCYAN "Start ${SERVER} ${SERVER_VERSION} Benchmarking >>>>>>>>"
        for TOOL in ${TOOL_LIST}; do
            echoB " - ${TOOL}"
            for TARGET in ${TARGET_LIST}; do
                load_param ${TOOL} ${TARGET}
                check_wp_target ${TARGET}
                echoY "      |--- https://${TMP_DOMAIN}/${TMP_TARGET}"  
                if [ ${CHECK} = 'ON' ]; then
                    sleep ${INTERVAL}
                    loop_check_server_cpu
                fi
                noext_target ${TARGET}
                sleep ${INTERVAL}
                validate_server ${TMP_DOMAIN} ${TMP_TARGET}
                if [ ${?} = 0 ] && [ "${STATUS}" = '200' ]; then
                    if [ ${CHECK} = 'ON' ]; then
                        sleep ${INTERVAL}
                        check_process_cpu ${TESTSERVERIP} ${SERVER} ${CMDFD}/log/${DATE}-${SERVER}-${FILENAME}-CPU-${TOOL};
                    fi    
                    sleep 1
                    for ((ROUND = 1; ROUND<=$ROUNDNUM; ROUND++)); do
                        echoY "          |--- ${ROUND} / ${ROUNDNUM}"

			MAPPINGLOG="${BENDATE}/${SERVER}/${FILENAME}-benchmark_${TOOL}.log.${ROUND}"

			if [ ${TOOL} = 'siege' ] && [ "${RUNSIEGE}" = 'true' ]; then
                            sleep ${INTERVAL}
                            siege_benchmark ${TMP_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [[ ${TOOL} == h2load* ]] && [ "${RUNH2LOAD}" = 'true' ]; then
                            sleep ${INTERVAL}
                            h2load_benchmark  ${TMP_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [ ${TOOL} = 'jmeter' ] && [ "${RUNJMETER}" = 'true' ]; then
                            sleep ${INTERVAL}
                            jmeter_benchmark ${TMP_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [ ${TOOL} = 'wrk' ] && [ "${RUNWRK}" = 'true' ]; then
                            sleep ${INTERVAL}
                            wrk_benchmark ${TMP_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                    done
                    if [ ${CHECK} = 'ON' ]; then
                        sleep ${INTERVAL}
                        kill_process_cpu ${TESTSERVERIP}
                    fi    
                else
                    echoR "[FAILED] to retrive target, Skip ${SERVER} testing"
                fi
            done
        done
        echoCYAN "End ${SERVER} ${SERVER_VERSION} Benchmarking <<<<<<<<"
    done
    echoG 'Benchmark testing ------End------'
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

sort_log(){
    for TARGET in ${TARGET_LIST}; do
        noext_target ${TARGET}
        check_wp_target ${TARGET}
        for TOOL in ${TOOL_LIST}; do              
            printf "\033[38;5;148m%s\033[39m\t\033[38;5;148m%s\033[39m\n"\
             "${TOOL}" "${PARAM_ARR[${TOOL}_${TARGET}]} https://${TMP_DOMAIN}/${TMP_TARGET}"
            for SERVER in ${SERVER_LIST}; do
                SORT_TARGET=${TARGET}
                get_server_version ${SERVER}

                local TIME_SPENT='0'
                local BANDWIDTH_PER_SECOND='0'
                local REQUESTS_PER_SECOND='0'
                local FAILED_REQUESTS='0'
                local REQUESTS_ARRAY=()
                local IGNORE_ARRAY=()
                local ITERATIONS='0'
                local BW_METRIC='MB'
                local TIME_METRIC='s'
                local TEMP_TIME_SPENT='0'
                local TEMP_BW_PS='0'
                local HEADER_COMPRESSION='0'

                if [[ ${ROUNDNUM} -ge 3 ]]; then
                    for ((ROUND=1; ROUND<=${ROUNDNUM}; ROUND++)); do
                        REQUESTS_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} \
                        | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $12}'))
                    done

                    IFS=$'\n' REQUESTS_ARRAY=($(sort <<< "${REQUESTS_ARRAY[*]}"))
                    unset IFS

                    IGNORE_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep ${SORT_TARGET} | grep ${TOOL} | grep ${SERVER} \
                    | grep ${SERVER_VERSION} | grep ${REQUESTS_ARRAY[0]} | head -n 1 | awk -F ',' '{print $2}'))
                    IGNORE_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep ${SORT_TARGET} | grep ${TOOL} | grep ${SERVER} \
                    | grep ${SERVER_VERSION} | grep ${REQUESTS_ARRAY[-1]} | head -n 1 | awk -F ',' '{print $2}'))
                fi

                for ((ROUND=1; ROUND<=${ROUNDNUM}; ROUND++)); do
                    if [[ ${IGNORE_ARRAY[@]} =~ ${ROUND} ]]; then
                        continue
                    fi
                    # Get Time Spent and convert to S is MS
                    TEMP_TIME_SPENT=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} \
                    | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $11}' | sed 's/.$//')
                    TIME_METRIC=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} \
                    | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $11}' | tail -c 3)
                    if [[ ${TIME_METRIC,,} == 'ms' ]]; then
                        TEMP_TIME_SPENT=$(awk "BEGIN {print ${TEMP_TIME_SPENT::-1}/1000}")
                    fi
                    TIME_SPENT=$(awk "BEGIN {print ${TIME_SPENT}+${TEMP_TIME_SPENT}}")
                    # Get BW Per Second and convert to MB if KB or GB
                    TEMP_BW_PS=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} \
                    | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $13}' | sed 's/.$//' | sed 's/.$//')
                    BW_METRIC=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} \
                    | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $13}' | tail -c 3)
                    if [[ ${BW_METRIC,,} != 'mb' ]]; then
                        if [[ ${BW_METRIC,,} == 'kb' ]]; then
                            TEMP_BW_PS=$(awk "BEGIN {print ${TEMP_BW_PS}/1024}")
                        elif [[ ${BW_METRIC,,} == 'gb' ]]; then
                            TEMP_BW_PS=$(awk "BEGIN {print ${TEMP_BW_PS}*1024}")
                        fi
                    fi
                    BANDWIDTH_PER_SECOND=$(awk "BEGIN {print ${BANDWIDTH_PER_SECOND}+${TEMP_BW_PS}}")
                    # Get Requests Per Second
                    REQUESTS_PER_SECOND=$(awk "BEGIN {print ${REQUESTS_PER_SECOND}+$(cat ${BENDATE}/${RESULT_NAME}.csv \
                    | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $12}')}")
                    # Get Failed requests and if tool is WRK just make FAILED_REQUESTS equal to N/A
                    if [[ ${TOOL} == 'wrk' ]]; then
                        FAILED_REQUESTS='N/A'
                        HEADER_COMPRESSION='N/A'
                    else
                        FAILED_REQUESTS=$(awk "BEGIN {print ${FAILED_REQUESTS}+$(cat ${BENDATE}/${RESULT_NAME}.csv \
                        | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $16}')}")
                        HEADER_COMPRESSION=$(awk "BEGIN {print ${HEADER_COMPRESSION}+$(cat ${BENDATE}/${RESULT_NAME}.csv \
                        | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} \
                        | awk -F ',' '{print $17}' | sed 's/.$//')}")
                    fi
                    ((++ITERATIONS))
                done

                TIME_SPENT=$(awk "BEGIN {print ${TIME_SPENT}/${ITERATIONS}}")
                BANDWIDTH_PER_SECOND=$(awk "BEGIN {print ${BANDWIDTH_PER_SECOND}/${ITERATIONS}}")
                REQUESTS_PER_SECOND=$(awk "BEGIN {print ${REQUESTS_PER_SECOND}/${ITERATIONS}}")
                if [[ ${TOOL} == 'wrk' ]]; then
                    FAILED_REQUESTS='N/A'
                    HEADER_COMPRESSION='N/A'
                else
                    FAILED_REQUESTS=$(awk "BEGIN {print ${FAILED_REQUESTS}/${ITERATIONS}}")
                    HEADER_COMPRESSION=$(awk "BEGIN {print ${HEADER_COMPRESSION}/${ITERATIONS}}")
                fi

                if [[ ${HEADER_COMPRESSION} != 'N/A' ]]; then
                    HEADER_COMPRESSION="${HEADER_COMPRESSION}%"
                fi

                printf "%-20s finished in %10.2f seconds, %10.2f req/s, %10.2f MB/s, %10s failures, %8s header compression\n" \
                "${SERVER} ${SERVER_VERSION}" "${TIME_SPENT}" "${REQUESTS_PER_SECOND}" "${BANDWIDTH_PER_SECOND}"\
                 "${FAILED_REQUESTS}" "${HEADER_COMPRESSION}"
            done
        done
    done
}


parse_log() {
    for SERVER in ${SERVER_LIST}; do
        get_server_version ${SERVER}
        for TOOL in ${TOOL_LIST}; do
            for TARGET in ${TARGET_LIST}; do
                noext_target ${TARGET}
		BENCHMARKLOG="benchmark_${TOOL}.log"
                if [[ ${TOOL} != h2load* ]]; then
                    PARSE_CONCURRENT_STREAMS='N/A'
                else
                    PARSE_CONCURRENT_STREAMS=${CONCURRENT_STREAMS}
                fi
                ${CLIENTTOOL}/parse.sh ${TOOL} "https://${TARGET_DOMAIN}/${TARGET}" ${BENDATE} \
                    "${SERVER}/${FILENAME}-${BENCHMARKLOG}" "${SERVER}-${TARGET}" ${SERVER} ${SERVER_VERSION} \
                    ${ROUNDNUM} ${PARSE_CONCURRENT_STREAMS}
            done
        done
    done
}


update_web_version(){
    for SERVER in ${SERVER_LIST}; do
        "${SSH[@]}" root@${TESTSERVERIP} "${CMDFD}/monitor.sh 'update_web_version' ${SERVER}" >/dev/null 2>&1
    done
}

gather_serverlog(){
    case ${1} in
        log)
        for SERVER in ${SERVER_LIST}; do
            scp -rq -i ~/.ssh/${SSHKEYNAME} root@${TESTSERVERIP}:${CMDFD}/log/${DATE}-${SERVER}* ${BENDATE}/${SERVER}/
        done
        ;;
        env)
        scp -rq -i ~/.ssh/${SSHKEYNAME} root@${TESTSERVERIP}:${ENVFD}/serveraccess.txt ${ENVFD}/server/
        scp -rq -i ~/.ssh/${SSHKEYNAME} root@${TESTSERVERIP}:${ENVFD}/server/* ${ENVFD}/server/
        cp -r ${ENVFD}/ ${BENDATE}/
        if [ ! -e ${BENDATE}/env ]; then
            echoR "${BENDATE}/env folder not found"
        fi
        ;;
    esac
}

archive_log(){
    if [ -e ${1}/${2}.csv ]; then
        silent tar -zcvf ${1}.tgz ${1}/
        if [ -e ${1}.tgz ]; then
            echoG "[OK] to archive ${1}.tgz"
        else
            echoR "[Failed] to archive ${1}.tgz"
        fi
    else
        echoR "[FAILED] to generate ${2}.csv"
    fi
}

main(){
    create_log_fd
    update_web_version
    gather_serverlog env
    help_message 3
    main_test
    parse_log
    if [ ${CHECK} = 'ON' ]; then
        gather_serverlog log
    fi    
    archive_log ${BENDATE} ${RESULT_NAME}
    help_message 2
    kill $KILL_PROCESS_LIST > /dev/null 2>&1
}

PROFILE=default.profile
while [ ! -z "${1}" ]; do
    case ${1} in
        -[hH] | -help | --help)
            help_message 1
            ;;
        -p | -P | --profile) shift
	    PROFILE=${1}
	    ;;
        -r | -R | --round) shift
            checkroundin ${1}
            ;;
        -i | -I | --interval) shift
            INTERVAL=${1}
            ;;
        --no-check)
            CHECK='OFF'
            ;;
	*.profile)
            PROFILE=${1}
            ;;

        *) echo
            'Not support'
            ;;
    esac
    shift
done
source ${CMDFD}/${PROFILE} && main
