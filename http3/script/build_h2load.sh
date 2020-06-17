
apt install libjemalloc* -y

apt install git g++ make binutils autoconf automake autotools-dev libtool pkg-config \
        zlib1g-dev libev-dev libc-ares-dev bison \
        zlib1g libev4 libc-ares2 ca-certificates psmisc \
        python -y -m

cd `dirname "$0"`
cd ..
PREFIX=`pwd`
mkdir src
cd src

git clone --depth 1 -b OpenSSL_1_1_1g-quic-draft-29 https://github.com/tatsuhiro-t/openssl && \
    cd openssl && ./config enable-tls1_3 --libdir=lib --openssldir=/etc/ssl no-shared no-dso no-tests && make && make install_sw && cd .. 

git clone --depth 1 https://github.com/ngtcp2/nghttp3 && \
    cd nghttp3 && autoreconf -i && \
    ./configure --enable-lib-only --disable-shared && \
    make && make install-strip && cd .. 

git clone --depth 1 https://github.com/ngtcp2/ngtcp2 && \
    cd ngtcp2 && autoreconf -i && \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig/" LIBS="-lpthread -ldl" CPPFLAGS="-D__STDC_FORMAT_MACROS" ./configure --disable-shared && \
    make && make install-strip && cd .. 

git clone --depth 1 -b quic https://github.com/nghttp2/nghttp2.git && \
    cd nghttp2 && \
    git submodule update --init && autoreconf -i && \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig/" LIBS="-lpthread -ldl" ./configure --disable-examples --disable-hpack-tools --disable-python-bindings --disable-shared --with-neverbleed && \
    make install-strip && \
    cd ..
cd ..
cp src/nghttp2/src/h2load /usr/local/bin/
