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

export NGINX_VERSION=1.19.6
export NDK_VERSION=0.3.1
export SETMISC_VERSION=0.32
export MORE_HEADERS_VERSION=0.33
export NGINX_DIGEST_AUTH=cd8641886c873cf543255aeda20d23e4cd603d05
export NGINX_SUBSTITUTIONS=bc58cb11844bc42735bbaef7085ea86ace46d05b
export MSGPACK_VERSION=3.2.1
export LUA_NGX_VERSION=138c1b96423aa26defe00fe64dd5760ef17e5ad8
export LUA_STREAM_NGX_VERSION=0.0.9
export LUA_UPSTREAM_VERSION=0.07
export LUA_CJSON_VERSION=2.1.0.8
export NGINX_INFLUXDB_VERSION=5b09391cb7b9a889687c0aa67964c06a2d933e8b
export GEOIP2_VERSION=3.3
export NGINX_AJP_VERSION=bf6cd93f2098b59260de8d494f0f4b1f11a84627

export LUAJIT_VERSION=2.1-20201027

export LUA_RESTY_BALANCER=af4508f7aa5560c7d810922c2515b557f9e5d51a
export LUA_RESTY_CACHE=0.10
export LUA_RESTY_CORE=0.1.21
export LUA_RESTY_COOKIE_VERSION=766ad8c15e498850ac77f5e0265f1d3f30dc4027
export LUA_RESTY_DNS=0.21
export LUA_RESTY_HTTP=0.15
export LUA_RESTY_LOCK=0.08
export LUA_RESTY_UPLOAD_VERSION=0.10
export LUA_RESTY_STRING_VERSION=0.12
export LUA_RESTY_MEMCACHED_VERSION=0.15
export LUA_RESTY_REDIS_VERSION=0.29
export LUA_RESTY_IPMATCHER_VERSION=1a0a1c58fd085b15eedee58de8b5f45c27aff7bc
export LUA_RESTY_GLOBAL_THROTTLE_VERSION=0.2.0

export BUILD_PATH=/tmp/build

ARCH=$(uname -m)

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
get_src b11195a02b1d3285ddf2987e02c6b6d28df41bb1b1dd25f33542848ef4fc33b5 \
        "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"

get_src 0e971105e210d272a497567fa2e2c256f4e39b845a5ba80d373e26ba1abfbd85 \
        "https://github.com/simpl/ngx_devel_kit/archive/v$NDK_VERSION.tar.gz"

get_src f1ad2459c4ee6a61771aa84f77871f4bfe42943a4aa4c30c62ba3f981f52c201 \
        "https://github.com/openresty/set-misc-nginx-module/archive/v$SETMISC_VERSION.tar.gz"

get_src a3dcbab117a9c103bc1ea5200fc00a7b7d2af97ff7fd525f16f8ac2632e30fbf \
        "https://github.com/openresty/headers-more-nginx-module/archive/v$MORE_HEADERS_VERSION.tar.gz"

get_src fe683831f832aae4737de1e1026a4454017c2d5f98cb88b08c5411dc380062f8 \
        "https://github.com/atomx/nginx-http-auth-digest/archive/$NGINX_DIGEST_AUTH.tar.gz"

get_src 618551948ab14cac51d6e4ad00452312c7b09938f59ebff4f93875013be31f2d \
        "https://github.com/yaoweibin/ngx_http_substitutions_filter_module/archive/$NGINX_SUBSTITUTIONS.tar.gz"

get_src 464f46744a6be778626d11452c4db3c2d09461080c6db42e358e21af19d542f6 \
        "https://github.com/msgpack/msgpack-c/archive/cpp-$MSGPACK_VERSION.tar.gz"

get_src 7dc05df3d1824b02c6958ff37f9e682b73c1737dcfee93212ca3f6c5bfae08f3 \
        "https://github.com/openresty/lua-nginx-module/archive/$LUA_NGX_VERSION.tar.gz"

get_src 6fcf7054f412a19c23c1ac3c0663f42f40bccc907d98c5d1657ae5cab9973ee9 \
        "https://github.com/openresty/stream-lua-nginx-module/archive/v$LUA_STREAM_NGX_VERSION.tar.gz"

get_src 2a69815e4ae01aa8b170941a8e1a10b6f6a9aab699dee485d58f021dd933829a \
        "https://github.com/openresty/lua-upstream-nginx-module/archive/v$LUA_UPSTREAM_VERSION.tar.gz"

get_src f74a0821b079ea1fd63dd8659064356fc3f421ff4b35c17877140d2b2841cc3b \
        "https://github.com/openresty/luajit2/archive/v$LUAJIT_VERSION.tar.gz"

get_src 1af5a5632dc8b00ae103d51b7bf225de3a7f0df82f5c6a401996c080106e600e \
        "https://github.com/influxdata/nginx-influxdb-module/archive/$NGINX_INFLUXDB_VERSION.tar.gz"

get_src 41378438c833e313a18869d0c4a72704b4835c30acaf7fd68013ab6732ff78a7 \
        "https://github.com/leev/ngx_http_geoip2_module/archive/$GEOIP2_VERSION.tar.gz"

get_src 5f629a50ba22347c441421091da70fdc2ac14586619934534e5a0f8a1390a950 \
        "https://github.com/yaoweibin/nginx_ajp_module/archive/$NGINX_AJP_VERSION.tar.gz"

get_src 5d16e623d17d4f42cc64ea9cfb69ca960d313e12f5d828f785dd227cc483fcbd \
        "https://github.com/openresty/lua-resty-upload/archive/v$LUA_RESTY_UPLOAD_VERSION.tar.gz"

get_src bfd8c4b6c90aa9dcbe047ac798593a41a3f21edcb71904d50d8ac0e8c77d1132 \
        "https://github.com/openresty/lua-resty-string/archive/v$LUA_RESTY_STRING_VERSION.tar.gz"

get_src a21ec0d78a5dc5856df2374890a8a58e51de866b3d5978aceb0109a094367630 \
        "https://github.com/openresty/lua-resty-balancer/archive/$LUA_RESTY_BALANCER.tar.gz"

get_src a377fbce78ba10f3ed3a8b5173ea318f8cf8da9d2ab127bb1e1f263078bf7da0 \
        "https://github.com/openresty/lua-resty-core/archive/v$LUA_RESTY_CORE.tar.gz"

get_src bd6bee4ccc6cf3307ab6ca0eea693a921fab9b067ba40ae12a652636da588ff7 \
        "https://github.com/openresty/lua-cjson/archive/$LUA_CJSON_VERSION.tar.gz"

get_src f818b5cef0881e5987606f2acda0e491531a0cb0c126d8dca02e2343edf641ef \
        "https://github.com/cloudflare/lua-resty-cookie/archive/$LUA_RESTY_COOKIE_VERSION.tar.gz"

get_src dae9fb572f04e7df0dabc228f21cdd8bbfa1ff88e682e983ef558585bc899de0 \
        "https://github.com/openresty/lua-resty-lrucache/archive/v$LUA_RESTY_CACHE.tar.gz"

get_src 2b4683f9abe73e18ca00345c65010c9056777970907a311d6e1699f753141de2 \
        "https://github.com/openresty/lua-resty-lock/archive/v$LUA_RESTY_LOCK.tar.gz"

get_src 4aca34f324d543754968359672dcf5f856234574ee4da360ce02c778d244572a \
        "https://github.com/openresty/lua-resty-dns/archive/v$LUA_RESTY_DNS.tar.gz"

get_src 987d5754a366d3ccbf745d2765f82595dcff5b94ba6c755eeb6d310447996f32 \
        "https://github.com/ledgetech/lua-resty-http/archive/v$LUA_RESTY_HTTP.tar.gz"

get_src 8257e8fbf78eb2cc2cf2fdca2fda3c2e755f7d3222e7d15cc322111a0f720f9c \
        "https://github.com/openresty/lua-resty-memcached/archive/v$LUA_RESTY_MEMCACHED_VERSION.tar.gz"

get_src 3f602af507aacd1f7aaeddfe7b77627fcde095fe9f115cb9d6ad8de2a52520e1 \
        "https://github.com/openresty/lua-resty-redis/archive/v$LUA_RESTY_REDIS_VERSION.tar.gz"

get_src d0eacda122ab36585936256cb222ea9147bc5ad1fc3f24fd3748475653dd27ad \
        "https://github.com/api7/lua-resty-ipmatcher/archive/$LUA_RESTY_IPMATCHER_VERSION.tar.gz"

get_src 0fb790e394510e73fdba1492e576aaec0b8ee9ef08e3e821ce253a07719cf7ea \
        "https://github.com/ElvinEfendi/lua-resty-global-throttle/archive/v$LUA_RESTY_GLOBAL_THROTTLE_VERSION.tar.gz"

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
  patch -p1 < /patches/$PATCH
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
CC_OPT="-g -Og -fPIE -fstack-protector-strong \
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
  CC_OPT+=' -m64 -mtune=native'
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
  --add-dynamic-module=$BUILD_PATH/nginx-influxdb-module-$NGINX_INFLUXDB_VERSION \
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

addgroup -Sg 101 www-data
adduser -S -D -H -u 101 -h /usr/local/nginx -s /sbin/nologin -G www-data -g www-data www-data

for dir in "${writeDirs[@]}"; do
  mkdir -p ${dir};
  chown -R www-data.www-data ${dir};
done

# remove .a files
find /usr/local -name "*.a" -print | xargs /bin/rm
