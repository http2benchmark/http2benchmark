#!/bin/sh

cd `dirname "$0"`


./build_nginx_quiche.sh
./nginx_http3_config.sh
./gen_test_files.sh
