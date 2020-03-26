#!/bin/sh

cd `dirname "$0"`

./build_h2load.sh
cp ../tools/config/* /opt/h2bench/tools/config/
cp ../http3.profile /opt/h2bench
sysctl -w net.core.rmem_max=26214400
sysctl -w net.core.rmem_max=26214400

