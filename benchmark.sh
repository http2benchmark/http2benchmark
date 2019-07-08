#!/usr/bin/env bash
# /********************************************************************
# HTTP2 Benchmark Script
# Version: 1.0
# *********************************************************************/

SERVER_LIST="lsws nginx"
#SERVER_LIST="apache lsws nginx"
TOOL_LIST="h2load wrk"
#TOOL_LIST="h2load jmeter"
TARGET_LIST="1kstatic.html 1knogzip.jpg wordpress"
#TARGET_LIST="1kstatic.html 1knogzip.jpg 10kstatic.html 100kstatic.html wordpress"

CPU_THRESHOLD=30
### Reduce the interval number if you have > 1 CPU
INTERVAL=20

DATE=$(date +%m%d%y-%H%M%S)
CMDFD='/opt'
SSHKEYNAME='http2'
ENVFD="${CMDFD}/env"
CLIENTTOOL="${CMDFD}/tools"
CLIENTCF="${CLIENTTOOL}/config"
TEST_IP="${ENVFD}/ip.log"
BENCHMARKLOG_H2="benchmark_H2.log"
BENCHMARKLOG_SG="benchmark_SG.log"
BENCHMARKLOG_JM="benchmark_JM.log"
BENCHMARKLOG_WK="benchmark_WK.log"
BENDATE="${CMDFD}/Benchmark/${DATE}"
LOG_APACHE="${BENDATE}/apache"
LOG_LSWS="${BENDATE}/lsws"
LOG_NGINX="${BENDATE}/nginx"
TESTSERVERIP="$(cat ${TEST_IP})"
SSH=(ssh -o 'StrictHostKeyChecking=no' -i ~/.ssh/${SSHKEYNAME})
JMFD='apache-jmeter'
JMPLAN='jmeter.jmx'
JMCFPATH="${CLIENTTOOL}/${JMFD}/bin/examples/${JMPLAN}"
RESULT_NAME='RESULTS'
FILE_CONTENT=""
LASTFIELD=''
KILL_PROCESS_LIST=''
TARGET_DOMAIN=""
HEADER='Accept-Encoding: gzip,deflate'
SERVER_VERSION='N/A'
ROUNDNUM=3
declare -A WEB_ARR=( [apache]=wp_apache/ [lsws]=wp_lsws/ [nginx]=wp_nginx/ )

###### H2Load
CONCURRENT_STREAMS=$(grep '\-m' ${CLIENTCF}/h2load.conf  | awk '{print $NF}')

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
echoB()
{
    echo -e "\033[1;3;94m${1}\033[0m"
}
echoNG() {
    echo -ne "\033[38;5;71m${1}\033[39m"
}
echoCYAN() {
    echo -e "\033[1;36m${1}\033[0m"
}

grep_1stcolumn2(){
    grep -m1 ${1} ${2} | awk -F '\"' '{print $2}'
}

help_message(){
    case ${1} in
        "1")
        local SERVER_L=$(grep_1stcolumn2 '^SERVER_LIST' ${0})
        local SERVER_L_SUPPORT=$(grep_1stcolumn2 '#SERVER_LIST' ${0})
        local TOOL_L=$(grep_1stcolumn2 '^TOOL_LIST' ${0})
        local TOOL_L_SUPPORT=$(grep_1stcolumn2 '#TOOL_LIST' ${0})
        local TARGET_L=$(grep_1stcolumn2 '^TARGET_LIST' ${0})
        local TARGET_L_SUPPORT=$(grep_1stcolumn2 '#TARGET_LIST' ${0})
        echo '######################################################################################'
        echo -e '# To customize tool PARAMETERS, e.g. h2load, please edit' $(echoB "${CLIENTCF}/h2load.conf")
        echo -e '# To customize which servers, tools and target to run, please edit' $(echoB "${0} ")
        echo -e '#' $(echoY "Server List: ${SERVER_L}")
        echo -e '#' $(echoG "Support val: ${SERVER_L_SUPPORT}")
        echo -e '#' $(echoY "Tools List : ${TOOL_L}")
        echo -e '#' $(echoG "Support val: ${TOOL_L_SUPPORT}")
        echo -e '#' $(echoY "Target List: ${TARGET_L}")
        echo -e '#' $(echoG "Support val: ${TARGET_L_SUPPORT}")
        echo '######################################################################################'
        exit 0
        ;;
        "2")
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
            #exit 1
        else
            ROUNDNUM=${1}
        fi
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

create_log_fd(){
    mkdir -p ${LOG_APACHE}
    mkdir -p ${LOG_LSWS}
    mkdir -p ${LOG_NGINX}
}

readwholefile(){
    if [ -e ${1} ]; then
        FILE_CONTENT=$(sed ':a;N;$!ba;s/\n/ /g' ${1})
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

target_check(){
    if [ ! -z ${3} ]; then
        echo "Check Target command: curl -H 'User-Agent: benchmark' -H "${HEADER}" -sILk https://${1}/${2}" >> ${3}
    fi
    echo "Target Response >>>>>>>>>>>>>>>>>>>>>>>"
    silent curl -H "User-Agent: benchmark" -H "${HEADER}" -siLk https://${1}/${2}
    curl -H "User-Agent: benchmark" -H "${HEADER}" -sILk https://${1}/${2}
    echo "Target Response <<<<<<<<<<<<<<<<<<<<<<<"
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
            ### Check Jmeter
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
        if [ ${TOOL} = 'h2load' ]; then
            ### Check h2load
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
            ### Check Siege
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
            ### Check wrk
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
    STATUS=$(curl -H "User-Agent: benchmark" -H "${HEADER}" -ILks -o /dev/null -w '%{http_code}' https://${1}/${2})
}

siege_benchmark(){
    MAPPINGLOG="${BENDATE}/${3}/${FILENAME}-${BENCHMARKLOG_SG}.${4}"
    echo "Target: https://${1}/${2}" >> ${MAPPINGLOG}
    target_check ${TESTSERVERIP} ${TARGET} ${MAPPINGLOG} >> ${MAPPINGLOG}
    echo "Benchmark Command: siege ${FILE_CONTENT} ${HEADER} https://${1}/${2}" >> ${MAPPINGLOG}
    siege ${FILE_CONTENT} "${HEADER}" "https://${1}/${2}" 1>/dev/null 2>> ${MAPPINGLOG}
}
h2load_benchmark(){
    MAPPINGLOG="${BENDATE}/${3}/${FILENAME}-${BENCHMARKLOG_H2}.${4}"
    echo "Target: https://${1}/${2}" >> ${MAPPINGLOG}
    target_check ${TESTSERVERIP} ${TARGET} ${MAPPINGLOG} >> ${MAPPINGLOG}
    echo "Benchmark Command: h2load ${FILE_CONTENT} ${HEADER} https://${1}/${2}" >> ${MAPPINGLOG}
    h2load ${FILE_CONTENT} "${HEADER}" "https://${1}/${2}" >> ${MAPPINGLOG}
}
jmeter_benchmark(){
    MAPPINGLOG="${BENDATE}/${3}/${FILENAME}-${BENCHMARKLOG_JM}.${4}"
    cd ${CLIENTTOOL}/${JMFD}/bin
    echo "Target: https://${1}/${2}" >> ${MAPPINGLOG}
    target_check ${TESTSERVERIP} ${TARGET} ${MAPPINGLOG} >> ${MAPPINGLOG}
    NEWKEY="          <stringProp name="HTTPSampler.domain">${1}/${2}</stringProp>"
    linechange 'HTTPSampler.domain' ${JMCFPATH} "${NEWKEY}"
    check_process_cpu ${TESTSERVERIP} ${SERVER} ${CMDFD}/log/${DATE}-${3}-${FILENAME}-CPU-${BENCHMARKLOG_JM}.${4}; sleep ${INTERVAL}
    #echo "Benchmark Command: jmeter.sh ${FILE_CONTENT} \${JMFD}" >> ${MAPPINGLOG}
    ./jmeter.sh ${FILE_CONTENT} "${JMFD}" >> ${MAPPINGLOG}
    kill_process_cpu ${TESTSERVERIP}
    cd ~
}
wrk_benchmark(){
    MAPPINGLOG="${BENDATE}/${3}/${FILENAME}-${BENCHMARKLOG_WK}.${4}"
    cd ${CLIENTTOOL}/wrk
    echo "Target: https://${1}/${2}" >> ${MAPPINGLOG}
    target_check ${TESTSERVERIP} ${TARGET} ${MAPPINGLOG} >> ${MAPPINGLOG}
    echo "Benchmark Command: wrk ${FILE_CONTENT} ${HEADER} https://${1}/${2}" >> ${MAPPINGLOG}
    ./wrk ${FILE_CONTENT} "${HEADER}" "https://${1}/${2}" >> ${MAPPINGLOG}
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
        if [ ${TESTSERVERCPU} -ge ${CPU_THRESHOLD} ]; then
            echoY "Test server: CPU ${TESTSERVERCPU}% is high, please wait.."
            sleep 30
        else
            break
        fi
    done
}

main_test(){
    START_TIME="$(date -u +%s)"
    validate_tool
    kill_process_cpu ${TESTSERVERIP}
    for SERVER in ${SERVER_LIST}; do
        server_switch ${TESTSERVERIP} ${SERVER}
        get_server_version ${SERVER}
        rdlastfield ${SERVER} "${CLIENTCF}/urls.conf"
        TARGET_DOMAIN="${LASTFIELD}"
        echoCYAN "Start ${SERVER} ${SERVER_VERSION} Benchmarking >>>>>>>>"
        for TOOL in ${TOOL_LIST}; do
            echoB " - ${TOOL}"
            readwholefile "${CLIENTCF}/${TOOL}.conf"
            for TARGET in ${TARGET_LIST}; do
                if [ "${TARGET}" = 'wordpress' ]; then
                    TARGET=${WEB_ARR["${SERVER}"]}
                fi
                echoY "      |--- https://${TARGET_DOMAIN}/${TARGET}"
                loop_check_server_cpu
                noext_target ${TARGET}
                validate_server ${TARGET_DOMAIN} ${TARGET}
                if [ ${?} = 0 ] && [ "${STATUS}" = '200' ]; then

                    check_process_cpu ${TESTSERVERIP} ${SERVER} ${CMDFD}/log/${DATE}-${SERVER}-${FILENAME}-CPU-${TOOL};
                    sleep 1
                    for ((ROUND = 1; ROUND<=$ROUNDNUM; ROUND++)); do
                        echoY "          |--- ${ROUND} / ${ROUNDNUM}"
                        #loop_check_server_cpu
                        if [ ${TOOL} = 'siege' ] && [ "${RUNSIEGE}" = 'true' ]; then
                            siege_benchmark ${TARGET_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [ ${TOOL} = 'h2load' ] && [ "${RUNH2LOAD}" = 'true' ]; then
                            h2load_benchmark  ${TARGET_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [ ${TOOL} = 'jmeter' ] && [ "${RUNJMETER}" = 'true' ]; then
                            jmeter_benchmark ${TARGET_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                        if [ ${TOOL} = 'wrk' ] && [ "${RUNWRK}" = 'true' ]; then
                            wrk_benchmark ${TARGET_DOMAIN} ${TARGET} ${SERVER} ${ROUND}
                        fi
                    done
                    kill_process_cpu ${TESTSERVERIP}
                else
                    echoR "[FAILED] to retrive target, Skip ${SERVER} testing"
                fi
            done
        done
        echoCYAN "End ${SERVER} ${SERVER_VERSION} Benchmarking <<<<<<<<"
    done
    echoG 'Benchmark testing ------End------'
    END_TIME="$(date -u +%s)"
    END_TIME="$(date -u +%s)"
    ELAPSED="$((${END_TIME}-${START_TIME}))"
    echoY "***Total of ${ELAPSED} seconds to finish process***"
}

sort_log(){
    for TARGET in ${TARGET_LIST}; do
        noext_target ${TARGET}
        for TOOL in ${TOOL_LIST}; do
            printf "%s - %s\n" "${TOOL}" "${TARGET}"
            for SERVER in ${SERVER_LIST}; do
                if [ "${TARGET}" = 'wordpress' ]; then
                    SORT_TARGET=${WEB_ARR["${SERVER}"]}
                else
                    SORT_TARGET=${TARGET}
                fi
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

                if [[ ${ROUNDNUM} -ge 3 ]]; then
                    for ((ROUND=1; ROUND<=${ROUNDNUM}; ROUND++)); do
                        REQUESTS_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $12}'))
                    done

                    IFS=$'\n' REQUESTS_ARRAY=($(sort <<< "${REQUESTS_ARRAY[*]}"))
                    unset IFS

                    IGNORE_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep ${SORT_TARGET} | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | grep ${REQUESTS_ARRAY[0]} | head -n 1 | awk -F ',' '{print $2}'))
                    IGNORE_ARRAY+=($(cat ${BENDATE}/${RESULT_NAME}.csv | grep ${SORT_TARGET} | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | grep ${REQUESTS_ARRAY[-1]} | head -n 1 | awk -F ',' '{print $2}'))
                fi

                for ((ROUND=1; ROUND<=${ROUNDNUM}; ROUND++)); do
                    if [[ ${IGNORE_ARRAY[@]} =~ ${ROUND} ]]; then
                        continue
                    fi
                    # Get Time Spent and convert to S is MS
                    TEMP_TIME_SPENT=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $11}' | sed 's/.$//')
                    TIME_METRIC=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $11}' | tail -c 3)
                    if [[ ${TIME_METRIC,,} == 'ms' ]]; then
                        TEMP_TIME_SPENT=$(awk "BEGIN {print ${TEMP_TIME_SPENT::-1}/1000}")
                    fi
                    TIME_SPENT=$(awk "BEGIN {print ${TIME_SPENT}+${TEMP_TIME_SPENT}}")
                    # Get BW Per Second and convert to MB if KB or GB
                    TEMP_BW_PS=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $13}' | sed 's/.$//' | sed 's/.$//')
                    BW_METRIC=$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $13}' | tail -c 3)
                    if [[ ${BW_METRIC,,} != 'mb' ]]; then
                        if [[ ${BW_METRIC,,} == 'kb' ]]; then
                            TEMP_BW_PS=$(awk "BEGIN {print ${TEMP_BW_PS}/1024}")
                        elif [[ ${BW_METRIC,,} == 'gb' ]]; then
                            TEMP_BW_PS=$(awk "BEGIN {print ${TEMP_BW_PS}*1024}")
                        fi
                    fi
                    BANDWIDTH_PER_SECOND=$(awk "BEGIN {print ${BANDWIDTH_PER_SECOND}+${TEMP_BW_PS}}")
                    # Get Requests Per Second
                    REQUESTS_PER_SECOND=$(awk "BEGIN {print ${REQUESTS_PER_SECOND}+$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $12}')}")
                    # Get Failed requests and if tool is WRK just make FAILED_REQUESTS equal to N/A
                    if [[ ${TOOL} == 'wrk' ]]; then
                        FAILED_REQUESTS='N/A'
                    else
                        FAILED_REQUESTS=$(awk "BEGIN {print ${FAILED_REQUESTS}+$(cat ${BENDATE}/${RESULT_NAME}.csv | grep "${SORT_TARGET},${ROUND}," | grep ${TOOL} | grep ${SERVER} | grep ${SERVER_VERSION} | awk -F ',' '{print $16}')}")
                    fi
                    ((++ITERATIONS))
                done

                TIME_SPENT=$(awk "BEGIN {print ${TIME_SPENT}/${ITERATIONS}}")
                BANDWIDTH_PER_SECOND=$(awk "BEGIN {print ${BANDWIDTH_PER_SECOND}/${ITERATIONS}}")
                REQUESTS_PER_SECOND=$(awk "BEGIN {print ${REQUESTS_PER_SECOND}/${ITERATIONS}}")
                if [[ ${TOOL} == 'wrk' ]]; then
                    FAILED_REQUESTS='N/A'
                else
                    FAILED_REQUESTS=$(awk "BEGIN {print ${FAILED_REQUESTS}/${ITERATIONS}}")
                fi

                printf "%-15s finished in %10.2f seconds, %10.2f req/s, %10.2f MB/s, %10s failures\n" "${SERVER} ${SERVER_VERSION}" "${TIME_SPENT}" "${REQUESTS_PER_SECOND}" "${BANDWIDTH_PER_SECOND}" "${FAILED_REQUESTS}"
            done
        done
    done
}

parse_log() {
    for SERVER in ${SERVER_LIST}; do
        get_server_version ${SERVER}
        for TOOL in ${TOOL_LIST}; do
            for TARGET in ${TARGET_LIST}; do
                if [ "${TARGET}" = 'wordpress' ]; then
                    TARGET=${WEB_ARR["${SERVER}"]}
                fi
                noext_target ${TARGET}
                case ${TOOL} in
                    siege)  BENCHMARKLOG=${BENCHMARKLOG_SG} ;;
                    h2load) BENCHMARKLOG=${BENCHMARKLOG_H2} ;;
                    jmeter) BENCHMARKLOG=${BENCHMARKLOG_JM} ;;
                    wrk)    BENCHMARKLOG=${BENCHMARKLOG_WK} ;;
                esac
                if [ ${TOOL} != 'h2load' ]; then
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
    gather_serverlog log
    archive_log ${BENDATE} ${RESULT_NAME}
    help_message 2
    kill $KILL_PROCESS_LIST > /dev/null 2>&1
}

while [ ! -z "${1}" ]; do
    case ${1} in
        -[hH] | -help | --help)
            help_message 1
            ;;
        -r | -R | --round) shift
            checkroundin ${1}
            ;;
        *) echo
            'Not support'
            ;;
    esac
    shift
done
main
