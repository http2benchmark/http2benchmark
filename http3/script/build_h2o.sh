#!/bin/sh

cd `dirname "$0"`

apt -y install cmake build-essential openssl libssl-dev zlib1g zlib1g-dev pkg-config libuv1-dev libwslay-dev php php-fpm
mkdir ../src
cd  ../src
git clone https://github.com/h2o/h2o.git
cd h2o
cmake .
make
if [ ! -e h2o ] ; then
        echo "Build failed.  See above"
        exit 1
fi
if [ -e /usr/bin/h2o -a ! -e /usr/bin/h2o.dist ] ; then
        mv /usr/bin/h2o /usr/bin/h2o.dist
fi
rm /usr/bin/h2o 2>/dev/null
cp h2o /usr/bin/h2o
cd ../../script


