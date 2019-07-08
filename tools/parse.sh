#!/usr/bin/env bash
# /********************************************************************
# HTTP2 Benchmark Parse Script
# *********************************************************************/

TEST_RAN='N/A'
SERVER_NAME='N/A'
SERVER_VERSION='N/A'
BENCHMARK_TOOL='N/A'
APPLICATION_PROTOCOL='N/A'
CONCURRENT_CONNECTIONS='N/A'
CONCURRENT_STREAMS='N/A'
URL='N/A'
TOTAL_TIME_SPENT='N/A'
REQUESTS_PER_SECOND='N/A'
BANDWIDTH_PER_SECOND='N/A'
TOTAL_BANDWIDTH='N/A'
TOTAL_REQUESTS='N/A'
TOTAL_FAILURES='N/A'
STATUS_CODE_STATS='N/A'

function parse_wrk() {
  local ITERATION="$1"
  CONCURRENT_CONNECTIONS=$(grep 'connections' ${LOG_FILE}.${ITERATION} | awk '{print $4}')
  TOTAL_TIME_SPENT=$(grep 'requests in' ${LOG_FILE}.${ITERATION} | awk '{print $4}' | sed 's/.$//')
  REQUESTS_PER_SECOND=$(grep 'Requests/sec:' ${LOG_FILE}.${ITERATION} | awk '{print $2}')
  BANDWIDTH_PER_SECOND=$(grep 'Transfer/sec:' ${LOG_FILE}.${ITERATION} | awk '{print $2}')
  TOTAL_BANDWIDTH=$(grep 'requests in' ${LOG_FILE}.${ITERATION} | awk '{print $5}')
  TOTAL_REQUESTS=$(grep 'requests in' ${LOG_FILE}.${ITERATION} | awk '{print $1}')
}

function parse_h2load() {
  local ITERATION="$1"
  APPLICATION_PROTOCOL=$(grep 'Application protocol:' ${LOG_FILE}.${ITERATION} | awk '{print $3}')
  CONCURRENT_CONNECTIONS=$(grep 'total client' ${LOG_FILE}.${ITERATION} | awk '{print $4}')
  TOTAL_TIME_SPENT=$(grep 'finished in' ${LOG_FILE}.${ITERATION} | awk '{print $3}' | sed 's/.$//')
  REQUESTS_PER_SECOND=$(grep 'finished in' ${LOG_FILE}.${ITERATION} | awk '{print $4}' | sed 's/.$//')
  BANDWIDTH_PER_SECOND=$(grep 'finished in' ${LOG_FILE}.${ITERATION} | awk '{print $6}' | sed 's/.$//' | sed 's/.$//')
  TOTAL_BANDWIDTH=$(grep 'traffic:' ${LOG_FILE}.${ITERATION} | awk '{print $2}')
  TOTAL_REQUESTS=$(grep 'requests:' ${LOG_FILE}.${ITERATION} | awk '{print $2}')
  local TOTAL_SUCCESS=$(grep 'requests:' ${LOG_FILE}.${ITERATION} | awk '{print $8}')
  if [[ ${TOTAL_REQUESTS} != ${TOTAL_SUCCESS} ]]; then
    TOTAL_FAILURES=$(( ${TOTAL_REQUESTS} - ${TOTAL_SUCCESS} ))
  else
    TOTAL_FAILURES='0'
  fi
  STATUS_CODE_STATS=$(grep 'status codes:' ${LOG_FILE}.${ITERATION} | perl -pe "s/status codes: (.*?)/\1/")
}

function generate_csv() {
  local ITERATION="${1}"
  if [[ ! -f ${WORKING_PATH}/RESULTS.csv ]]; then
    printf "Test Ran,Iteration,Log File,Server Name,Server Version,Benchmark Tool,Concurrent Connections,Concurrent Streams,URL,Application Protocol,Total Time Spent,Requests Per Second,Bandwidth Per Second,Total Bandwidth,Total Requests,Total Failures,Status Code Stats\n" >> ${WORKING_PATH}/RESULTS.csv
  fi
    printf "${TEST_RAN},${ITERATION},${LOG_FILE},${SERVER_NAME},${SERVER_VERSION},${BENCHMARK_TOOL},${CONCURRENT_CONNECTIONS},${CONCURRENT_STREAMS},${URL},${APPLICATION_PROTOCOL},${TOTAL_TIME_SPENT},${REQUESTS_PER_SECOND},${BANDWIDTH_PER_SECOND},${TOTAL_BANDWIDTH},${TOTAL_REQUESTS},${TOTAL_FAILURES},${STATUS_CODE_STATS//,}\n" >> ${WORKING_PATH}/RESULTS.csv
}

function pretty_display() {
  local ITERATION="${1}"
  cat >> ${WORKING_PATH}/RESULTS.txt << EOF
############### ${TEST_RAN}.${ITERATION} ###############
Server Name:            ${SERVER_NAME}
Server Version:         ${SERVER_VERSION}
Benchmark Tool:         ${BENCHMARK_TOOL}
URL:                    ${URL}
Application Protocol:   ${APPLICATION_PROTOCOL}
Total Time Spent:       ${TOTAL_TIME_SPENT}
Concurrent Connections: ${CONCURRENT_CONNECTIONS}
Concurrent Streams:     ${CONCURRENT_STREAMS}
Total Requests:         ${TOTAL_REQUESTS}
Requests Per Second:    ${REQUESTS_PER_SECOND}
Total Bandwidth:        ${TOTAL_BANDWIDTH}
Bandwidth Per Second:   ${BANDWIDTH_PER_SECOND}
Total Failures:         ${TOTAL_FAILURES}
Status Code Stats:      ${STATUS_CODE_STATS}

EOF
}

function main() {
  if [[ $1 == '' ]]; then
    exit 1
  else
    if [[ $# -lt 6 ]]; then
      exit 1
    else
      BENCHMARK_TOOL="$1"
      URL="$2"
      WORKING_PATH="$3"
      LOG_FILE="${WORKING_PATH}/$4"
      TEST_RAN="$5"
      SERVER_NAME="$6"
      SERVER_VERSION="$7"
      ITERATIONS="$8"
      CONCURRENT_STREAMS="$9"
    fi
  fi

  for (( ITERATION = 1; ITERATION<=${ITERATIONS}; ITERATION++)); do
    if [[ ${BENCHMARK_TOOL} == 'h2load' ]]; then
      parse_h2load ${ITERATION}
    elif [[ ${BENCHMARK_TOOL} == 'wrk' ]]; then
      parse_wrk ${ITERATION}
    fi

    generate_csv "${ITERATION}"
    pretty_display "${ITERATION}"
  done

  exit 0
}

main "$@"