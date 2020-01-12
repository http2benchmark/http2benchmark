
cd `dirname "$0"`
cd ..
PREFIX=`pwd`
mkdir src
cd src

apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates coreutils curl git make cmake golang mercurial ssh \
    build-essential clang gyp ninja-build pkg-config zlib1g-dev \
 && apt-get autoremove -y && apt-get clean -y 

export RUSTUP_HOME=/usr/local/rustup 
export CARGO_HOME=/usr/local/cargo 
export PATH=/usr/local/cargo/bin:$PATH 
export RUST_VERSION=stable

set -eux; \
curl -sSLf "https://static.rust-lang.org/rustup/archive/1.20.2/x86_64-unknown-linux-gnu/rustup-init" -o rustup-init; \
echo 'e68f193542c68ce83c449809d2cad262cc2bbb99640eb47c58fc1dc58cc30add *rustup-init' | sha256sum -c -; \
chmod +x rustup-init; \
./rustup-init -y --no-modify-path --default-toolchain "$RUST_VERSION"; \
    rm -f rustup-init; \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME; \
    rustup component add clippy rustfmt; \
    rustup --version; \
    cargo --version; \
    rustc --version; \
    rustfmt --version

git clone --recurse-submodules --depth 1 https://github.com/cloudflare/quiche
cd quiche && \
	cargo build --release --examples

cd ..


curl -O https://nginx.org/download/nginx-1.16.1.tar.gz
tar xzvf nginx-1.16.1.tar.gz

cd nginx-1.16.1
patch -p1 < ../quiche/extras/nginx/nginx-1.16.patch

./configure                                 \
       --prefix=/usr                           \
       --build="quiche-$(git --git-dir=../quiche/.git rev-parse --short HEAD)" \
       --with-http_ssl_module                  \
       --with-http_v2_module                   \
       --with-http_v3_module                   \
       --with-openssl=../quiche/deps/boringssl \
       --with-quiche=../quiche
make -j4

cp objs/nginx /usr/sbin/nginx

