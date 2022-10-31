#!/bin/bash

# Copyright 2015 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

export NGINX_VERSION=1.19.10

# Check for recent changes: https://github.com/vision5/ngx_devel_kit/compare/v0.3.1...master
export NDK_VERSION=0.3.1

# Check for recent changes: https://github.com/openresty/set-misc-nginx-module/compare/v0.32...master
export SETMISC_VERSION=0.32

# Check for recent changes: https://github.com/openresty/headers-more-nginx-module/compare/v0.33...master
export MORE_HEADERS_VERSION=0.33

# Check for recent changes: https://github.com/atomx/nginx-http-auth-digest/compare/v1.0.0...atomx:master
export NGINX_DIGEST_AUTH=1.0.0

# Check for recent changes: https://github.com/yaoweibin/ngx_http_substitutions_filter_module/compare/v0.6.4...master
export NGINX_SUBSTITUTIONS=b8a71eacc7f986ba091282ab8b1bbbc6ae1807e0

# Check for recent changes: https://github.com/msgpack/msgpack-c/compare/cpp-3.3.0...master
export MSGPACK_VERSION=3.3.0

# Check for recent changes: https://github.com/openresty/lua-nginx-module/compare/v0.10.20...master
export LUA_NGX_VERSION=b721656a9127255003b696b42ccc871c7ec18d59

# Check for recent changes: https://github.com/openresty/stream-lua-nginx-module/compare/v0.0.10...master
export LUA_STREAM_NGX_VERSION=74f8c8bca5b95cecbf42d4e1a465bc08cd075a9b

# Check for recent changes: https://github.com/openresty/lua-upstream-nginx-module/compare/v0.07...master
export LUA_UPSTREAM_VERSION=8aa93ead98ba2060d4efd594ae33a35d153589bf

# Check for recent changes: https://github.com/openresty/lua-cjson/compare/2.1.0.8...openresty:master
export LUA_CJSON_VERSION=4b350c531de3d71008c77ae94e59275b8371b4dc

# Check for recent changes: https://github.com/leev/ngx_http_geoip2_module/compare/3.3...master
export GEOIP2_VERSION=a26c6beed77e81553686852dceb6c7fdacc5970d

# Check for recent changes: https://github.com/yaoweibin/nginx_ajp_module/compare/v0.3.0...master
export NGINX_AJP_VERSION=a964a0bcc6a9f2bfb82a13752d7794a36319ffac

# Check for recent changes: https://github.com/openresty/luajit2/compare/v2.1-20210510...v2.1-agentzh
export LUAJIT_VERSION=2.1-20210510

# Check for recent changes: https://github.com/openresty/lua-resty-balancer/compare/v0.04...master
export LUA_RESTY_BALANCER=0.04

# Check for recent changes: https://github.com/openresty/lua-resty-lrucache/compare/v0.11...master
export LUA_RESTY_CACHE=0.11

# Check for recent changes: https://github.com/openresty/lua-resty-core/compare/v0.1.22...master
export LUA_RESTY_CORE=0.1.22

# Check for recent changes: https://github.com/cloudflare/lua-resty-cookie/compare/v0.1.0...master
export LUA_RESTY_COOKIE_VERSION=303e32e512defced053a6484bc0745cf9dc0d39e

# Check for recent changes: https://github.com/openresty/lua-resty-dns/compare/v0.22...master
export LUA_RESTY_DNS=0.22

# Check for recent changes: https://github.com/ledgetech/lua-resty-http/compare/v0.16.1...master
export LUA_RESTY_HTTP=0ce55d6d15da140ecc5966fa848204c6fd9074e8

# Check for recent changes: https://github.com/openresty/lua-resty-lock/compare/v0.08...master
export LUA_RESTY_LOCK=0.08

# Check for recent changes: https://github.com/openresty/lua-resty-upload/compare/v0.10...master
export LUA_RESTY_UPLOAD_VERSION=0.10

# Check for recent changes: https://github.com/openresty/lua-resty-string/compare/v0.14...master
export LUA_RESTY_STRING_VERSION=9ace36f2dde09451c377c839117ade45eb02d460

# Check for recent changes: https://github.com/openresty/lua-resty-memcached/compare/v0.16...master
export LUA_RESTY_MEMCACHED_VERSION=0.16

# Check for recent changes: https://github.com/openresty/lua-resty-redis/compare/v0.29...master
export LUA_RESTY_REDIS_VERSION=0.29

# Check for recent changes: https://github.com/api7/lua-resty-ipmatcher/compare/v0.6...master
export LUA_RESTY_IPMATCHER_VERSION=211e0d2eb8bbb558b79368f89948a0bafdc23654

# Check for recent changes: https://github.com/ElvinEfendi/lua-resty-global-throttle/compare/v0.2.0...main
export LUA_RESTY_GLOBAL_THROTTLE_VERSION=0.2.0

# Check for recent changes: https://github.com/starwing/lua-protobuf/compare/0.3.4...master
export LUA_PROTOBUF_VERSION=0.3.4

# Check for recent changes: https://github.com/yangxikun/opentelemetry-lua/compare/0.2.1...master
# Update tags in plugins/opentelemetry/statsd.lua when updating this.
export LUA_OPENTELEMETRY_VERSION=0.2.1

export BUILD_PATH=/tmp/build

ARCH=$(uname -m)

if [[ ${ARCH} == "s390x" ]]; then
  export LUAJIT_VERSION=9d5750d28478abfdcaefdfdc408f87752a21e431
  export LUA_RESTY_CORE=0.1.17
  export LUA_NGX_VERSION=0.10.15
  export LUA_STREAM_NGX_VERSION=0.0.7
fi

get_src()
{
  hash="$1"
  url="$2"
  f=$(basename "$url")

  echo "Downloading $url"

  curl -sSL "$url" -o "$f"
  echo "$hash  $f" | sha256sum -c - || exit 10
  tar xzf "$f"
  rm -rf "$f"
}

# install required packages to build
apk add \
  bash \
  gcc \
  clang \
  libc-dev \
  make \
  automake \
  openssl-dev \
  pcre-dev \
  zlib-dev \
  linux-headers \
  libxslt-dev \
  gd-dev \
  geoip-dev \
  perl-dev \
  libedit-dev \
  mercurial \
  alpine-sdk \
  findutils \
  curl ca-certificates \
  patch \
  libaio-dev \
  openssl \
  cmake \
  util-linux \
  lmdb-tools \
  wget \
  curl-dev \
  libprotobuf \
  git g++ pkgconf flex bison doxygen yajl-dev lmdb-dev libtool autoconf libxml2 libxml2-dev \
  python3 \
  libmaxminddb-dev \
  bc \
  unzip \
  dos2unix \
  yaml-cpp \
  coreutils

mkdir -p /etc/nginx

mkdir --verbose -p "$BUILD_PATH"
cd "$BUILD_PATH"

# download, verify and extract the source files
get_src e8d0290ff561986ad7cd6c33307e12e11b137186c4403a6a5ccdb4914c082d88 \
        "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"

get_src 0e971105e210d272a497567fa2e2c256f4e39b845a5ba80d373e26ba1abfbd85 \
        "https://github.com/simpl/ngx_devel_kit/archive/v$NDK_VERSION.tar.gz"

get_src f1ad2459c4ee6a61771aa84f77871f4bfe42943a4aa4c30c62ba3f981f52c201 \
        "https://github.com/openresty/set-misc-nginx-module/archive/v$SETMISC_VERSION.tar.gz"

get_src a3dcbab117a9c103bc1ea5200fc00a7b7d2af97ff7fd525f16f8ac2632e30fbf \
        "https://github.com/openresty/headers-more-nginx-module/archive/v$MORE_HEADERS_VERSION.tar.gz"

get_src f09851e6309560a8ff3e901548405066c83f1f6ff88aa7171e0763bd9514762b \
        "https://github.com/atomx/nginx-http-auth-digest/archive/v$NGINX_DIGEST_AUTH.tar.gz"

get_src a98b48947359166326d58700ccdc27256d2648218072da138ab6b47de47fbd8f \
        "https://github.com/yaoweibin/ngx_http_substitutions_filter_module/archive/$NGINX_SUBSTITUTIONS.tar.gz"

get_src 754c3ace499a63e45b77ef4bcab4ee602c2c414f58403bce826b76ffc2f77d0b \
        "https://github.com/msgpack/msgpack-c/archive/cpp-$MSGPACK_VERSION.tar.gz"

if [[ ${ARCH} == "s390x" ]]; then
get_src 7d5f3439c8df56046d0564b5857fd8a30296ab1bd6df0f048aed7afb56a0a4c2 \
        "https://github.com/openresty/lua-nginx-module/archive/v$LUA_NGX_VERSION.tar.gz"
get_src 99c47c75c159795c9faf76bbb9fa58e5a50b75286c86565ffcec8514b1c74bf9 \
        "https://github.com/openresty/stream-lua-nginx-module/archive/v$LUA_STREAM_NGX_VERSION.tar.gz"
else
get_src 085a9fb2bf9c4466977595a5fe5156d76f3a2d9a2a81be3cacaff2021773393e \
        "https://github.com/openresty/lua-nginx-module/archive/$LUA_NGX_VERSION.tar.gz"

get_src ba38c9f8e4265836ba7f2ac559ddf140693ff2f5ae33ab1e384f51f3992151ab \
        "https://github.com/openresty/stream-lua-nginx-module/archive/$LUA_STREAM_NGX_VERSION.tar.gz"

fi

get_src a92c9ee6682567605ece55d4eed5d1d54446ba6fba748cff0a2482aea5713d5f \
        "https://github.com/openresty/lua-upstream-nginx-module/archive/$LUA_UPSTREAM_VERSION.tar.gz"

if [[ ${ARCH} == "s390x" ]]; then
get_src 266ed1abb70a9806d97cb958537a44b67db6afb33d3b32292a2d68a2acedea75 \
        "https://github.com/openresty/luajit2/archive/$LUAJIT_VERSION.tar.gz"
else
get_src 1ee6dad809a5bb22efb45e6dac767f7ce544ad652d353a93d7f26b605f69fe3f \
        "https://github.com/openresty/luajit2/archive/v$LUAJIT_VERSION.tar.gz"
fi

get_src 4c1933434572226942c65b2f2b26c8a536ab76aa771a3c7f6c2629faa764976b \
        "https://github.com/leev/ngx_http_geoip2_module/archive/$GEOIP2_VERSION.tar.gz"

get_src 94d1512bf0e5e6ffa4eca0489db1279d51f45386fffcb8a1d2d9f7fe93518465 \
        "https://github.com/yaoweibin/nginx_ajp_module/archive/$NGINX_AJP_VERSION.tar.gz"

get_src 5d16e623d17d4f42cc64ea9cfb69ca960d313e12f5d828f785dd227cc483fcbd \
        "https://github.com/openresty/lua-resty-upload/archive/v$LUA_RESTY_UPLOAD_VERSION.tar.gz"

get_src 462c6b38792bab4ca8212bdfd3f2e38f6883bb45c8fb8a03474ea813e0fab853 \
        "https://github.com/openresty/lua-resty-string/archive/$LUA_RESTY_STRING_VERSION.tar.gz"

get_src 16d72ed133f0c6df376a327386c3ef4e9406cf51003a700737c3805770ade7c5 \
        "https://github.com/openresty/lua-resty-balancer/archive/v$LUA_RESTY_BALANCER.tar.gz"

if [[ ${ARCH} == "s390x" ]]; then
get_src 8f5f76d2689a3f6b0782f0a009c56a65e4c7a4382be86422c9b3549fe95b0dc4 \
        "https://github.com/openresty/lua-resty-core/archive/v$LUA_RESTY_CORE.tar.gz"
else
get_src 4d971f711fad48c097070457c128ca36053835d8a3ba25a937e9991547d55d4d \
        "https://github.com/openresty/lua-resty-core/archive/v$LUA_RESTY_CORE.tar.gz"
fi

get_src 8d602af2669fb386931760916a39f6c9034f2363c4965f215042c086b8215238 \
        "https://github.com/openresty/lua-cjson/archive/$LUA_CJSON_VERSION.tar.gz"

get_src 5ed48c36231e2622b001308622d46a0077525ac2f751e8cc0c9905914254baa4 \
        "https://github.com/cloudflare/lua-resty-cookie/archive/$LUA_RESTY_COOKIE_VERSION.tar.gz"

get_src e810ed124fe788b8e4aac2c8960dda1b9a6f8d0ca94ce162f28d3f4d877df8af \
        "https://github.com/openresty/lua-resty-lrucache/archive/v$LUA_RESTY_CACHE.tar.gz"

get_src 2b4683f9abe73e18ca00345c65010c9056777970907a311d6e1699f753141de2 \
        "https://github.com/openresty/lua-resty-lock/archive/v$LUA_RESTY_LOCK.tar.gz"

get_src 70e9a01eb32ccade0d5116a25bcffde0445b94ad35035ce06b94ccd260ad1bf0 \
        "https://github.com/openresty/lua-resty-dns/archive/v$LUA_RESTY_DNS.tar.gz"

get_src 9fcb6db95bc37b6fce77d3b3dc740d593f9d90dce0369b405eb04844d56ac43f \
        "https://github.com/ledgetech/lua-resty-http/archive/$LUA_RESTY_HTTP.tar.gz"

get_src 42893da0e3de4ec180c9bf02f82608d78787290a70c5644b538f29d243147396 \
        "https://github.com/openresty/lua-resty-memcached/archive/v$LUA_RESTY_MEMCACHED_VERSION.tar.gz"

get_src 3f602af507aacd1f7aaeddfe7b77627fcde095fe9f115cb9d6ad8de2a52520e1 \
        "https://github.com/openresty/lua-resty-redis/archive/v$LUA_RESTY_REDIS_VERSION.tar.gz"

get_src b8dbd502751140993a852381bcd8e98a402454596bd91838c1e51268d42db261 \
        "https://github.com/api7/lua-resty-ipmatcher/archive/$LUA_RESTY_IPMATCHER_VERSION.tar.gz"

get_src 0fb790e394510e73fdba1492e576aaec0b8ee9ef08e3e821ce253a07719cf7ea \
        "https://github.com/ElvinEfendi/lua-resty-global-throttle/archive/v$LUA_RESTY_GLOBAL_THROTTLE_VERSION.tar.gz"

get_src cb27d08c888aca5ff8ab4c72fd9ccdd85dbe0d69b2850a6e0e9751ed9de613f3 \
    "https://github.com/starwing/lua-protobuf/archive/refs/tags/$LUA_PROTOBUF_VERSION.tar.gz"

get_src b0ce4d3bd8449efd5bb0f24ccc7183b10e02cbaab7b90d90f7ca0d591077b388 \
    "https://github.com/yangxikun/opentelemetry-lua/archive/refs/tags/v$LUA_OPENTELEMETRY_VERSION.tar.gz"


# Install luajit from openresty fork
export LUAJIT_LIB=/usr/local/lib
export LUA_LIB_DIR="$LUAJIT_LIB/lua"
export LUAJIT_INC=/usr/local/include/luajit-2.1

cd "$BUILD_PATH/luajit2-$LUAJIT_VERSION"
make CCDEBUG=-g
make install

ln -s /usr/local/bin/luajit /usr/local/bin/lua
ln -s "$LUAJIT_INC" /usr/local/include/lua

cd "$BUILD_PATH"

# Git tuning
git config --global --add core.compression -1

# build msgpack lib
cd "$BUILD_PATH/msgpack-c-cpp-$MSGPACK_VERSION"

mkdir .build
cd .build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DMSGPACK_BUILD_EXAMPLES=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=true \
      ..

make
make install

# Get Brotli source and deps
cd "$BUILD_PATH"
git clone --depth=1 https://github.com/google/ngx_brotli.git
cd ngx_brotli
git submodule init
git submodule update

cd "$BUILD_PATH"
git clone --depth=1 https://github.com/ssdeep-project/ssdeep
cd ssdeep/

./bootstrap
./configure

make
make install

# build nginx
cd "$BUILD_PATH/nginx-$NGINX_VERSION"

# apply nginx patches
for PATCH in `ls /patches`;do
  echo "Patch: $PATCH"
  if [[ "$PATCH" == *.txt ]]; then
    patch -p0 < /patches/$PATCH
  else
    patch -p1 < /patches/$PATCH
  fi
done

WITH_FLAGS="--with-debug \
  --with-compat \
  --with-pcre-jit \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_auth_request_module \
  --with-http_addition_module \
  --with-http_geoip_module \
  --with-http_gzip_static_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-stream_realip_module \
  --with-stream_ssl_preread_module \
  --with-threads \
  --with-http_secure_link_module \
  --with-http_gunzip_module"

# "Combining -flto with -g is currently experimental and expected to produce unexpected results."
# https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html
CC_OPT="-g -O2 -fPIE -fstack-protector-strong \
  -Wformat \
  -Werror=format-security \
  -Wno-deprecated-declarations \
  -fno-strict-aliasing \
  -D_FORTIFY_SOURCE=2 \
  --param=ssp-buffer-size=4 \
  -DTCP_FASTOPEN=23 \
  -fPIC \
  -Wno-cast-function-type"

LD_OPT="-fPIE -fPIC -pie -Wl,-z,relro -Wl,-z,now"


if [[ ${ARCH} != "aarch64" ]]; then
  WITH_FLAGS+=" --with-file-aio"
fi

if [[ ${ARCH} == "x86_64" ]]; then
  CC_OPT+=' -m64 -mtune=generic'
fi

WITH_MODULES=" \
  --add-module=$BUILD_PATH/ngx_devel_kit-$NDK_VERSION \
  --add-module=$BUILD_PATH/set-misc-nginx-module-$SETMISC_VERSION \
  --add-module=$BUILD_PATH/headers-more-nginx-module-$MORE_HEADERS_VERSION \
  --add-module=$BUILD_PATH/ngx_http_substitutions_filter_module-$NGINX_SUBSTITUTIONS \
  --add-module=$BUILD_PATH/lua-nginx-module-$LUA_NGX_VERSION \
  --add-module=$BUILD_PATH/stream-lua-nginx-module-$LUA_STREAM_NGX_VERSION \
  --add-module=$BUILD_PATH/lua-upstream-nginx-module-$LUA_UPSTREAM_VERSION \
  --add-module=$BUILD_PATH/nginx_ajp_module-${NGINX_AJP_VERSION} \
  --add-dynamic-module=$BUILD_PATH/nginx-http-auth-digest-$NGINX_DIGEST_AUTH \
  --add-dynamic-module=$BUILD_PATH/ngx_http_geoip2_module-${GEOIP2_VERSION} \
  --add-dynamic-module=$BUILD_PATH/ngx_brotli"

./configure \
  --prefix=/usr/local/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --modules-path=/etc/nginx/modules \
  --http-log-path=/var/log/nginx/access.log \
  --error-log-path=/var/log/nginx/error.log \
  --lock-path=/var/lock/nginx.lock \
  --pid-path=/run/nginx.pid \
  --http-client-body-temp-path=/var/lib/nginx/body \
  --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
  --http-proxy-temp-path=/var/lib/nginx/proxy \
  --http-scgi-temp-path=/var/lib/nginx/scgi \
  --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
  ${WITH_FLAGS} \
  --without-mail_pop3_module \
  --without-mail_smtp_module \
  --without-mail_imap_module \
  --without-http_uwsgi_module \
  --without-http_scgi_module \
  --with-cc-opt="${CC_OPT}" \
  --with-ld-opt="${LD_OPT}" \
  --user=www-data \
  --group=www-data \
  ${WITH_MODULES}

make
make modules
make install

cd "$BUILD_PATH/lua-resty-core-$LUA_RESTY_CORE"
make install

cd "$BUILD_PATH/lua-resty-balancer-$LUA_RESTY_BALANCER"
make all
make install

export LUA_INCLUDE_DIR=/usr/local/include/luajit-2.1
ln -s $LUA_INCLUDE_DIR /usr/include/lua5.1

cd "$BUILD_PATH/lua-cjson-$LUA_CJSON_VERSION"
make all
make install

cd "$BUILD_PATH/lua-resty-cookie-$LUA_RESTY_COOKIE_VERSION"
make all
make install

cd "$BUILD_PATH/lua-resty-lrucache-$LUA_RESTY_CACHE"
make install

cd "$BUILD_PATH/lua-resty-dns-$LUA_RESTY_DNS"
make install

cd "$BUILD_PATH/lua-resty-lock-$LUA_RESTY_LOCK"
make install

# required for OCSP verification
cd "$BUILD_PATH/lua-resty-http-$LUA_RESTY_HTTP"
make install

cd "$BUILD_PATH/lua-resty-upload-$LUA_RESTY_UPLOAD_VERSION"
make install

cd "$BUILD_PATH/lua-resty-string-$LUA_RESTY_STRING_VERSION"
make install

cd "$BUILD_PATH/lua-resty-memcached-$LUA_RESTY_MEMCACHED_VERSION"
make install

cd "$BUILD_PATH/lua-resty-redis-$LUA_RESTY_REDIS_VERSION"
make install

cd "$BUILD_PATH/lua-resty-ipmatcher-$LUA_RESTY_IPMATCHER_VERSION"
INST_LUADIR=/usr/local/lib/lua make install

cd "$BUILD_PATH/lua-resty-global-throttle-$LUA_RESTY_GLOBAL_THROTTLE_VERSION"
make install

cd "$BUILD_PATH/lua-protobuf-$LUA_PROTOBUF_VERSION" \
        && gcc -O2 -shared -fPIC -I "/usr/local/include/luajit-2.1" pb.c -o pb.so \
        && install pb.so $LUAJIT_LIB/lua \
        && install protoc.lua $LUAJIT_LIB/lua

cd "$BUILD_PATH/opentelemetry-lua-$LUA_OPENTELEMETRY_VERSION" \
        && install -d $LUA_LIB_DIR/opentelemetry \
        && cd ./lib/opentelemetry \
        && find . -type f -exec install -Dm 755 "{}" "$LUA_LIB_DIR/opentelemetry/{}" \;

# mimalloc
cd "$BUILD_PATH"
git clone --depth=1 -b v1.6.7 https://github.com/microsoft/mimalloc
cd mimalloc

mkdir -p out/release
cd out/release

cmake ../..

make
make install

# update image permissions
writeDirs=( \
  /etc/nginx \
  /usr/local/nginx \
  /opt/modsecurity/var/log \
  /opt/modsecurity/var/upload \
  /opt/modsecurity/var/audit \
  /var/log/audit \
  /var/log/nginx \
);

adduser -S -D -H -u 101 -h /usr/local/nginx -s /sbin/nologin -G www-data -g www-data www-data

for dir in "${writeDirs[@]}"; do
  mkdir -p ${dir};
  chown -R www-data.www-data ${dir};
done

# remove .a files
find /usr/local -name "*.a" -print | xargs /bin/rm
