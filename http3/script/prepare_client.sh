#!/bin/sh

cd `dirname "$0"`

./build_h2load.sh
cp ../tools/config/* /opt/tools/config/
cp ../http3.profile /opt

