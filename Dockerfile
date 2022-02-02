ARG BASE_IMAGE

FROM k8s.gcr.io/ingress-nginx/e2e-test-runner:v20220110-gfd820db46@sha256:273f7d9b1b2297cd96b4d51600e45d932186a1cc79d00d179dfb43654112fe8f as go_builder

# ARCH=$(which go >/dev/null 2>&1 && go env GOARCH)
# REPO_INFO=$(git config --get remote.origin.url)
# TAG=$(cat TAG)

ARG ARCH
ARG TAG
ARG COMMIT_SHA

COPY . /

RUN PKG=k8s.io/ingress-nginx \
    ARCH=${ARCH} \
    COMMIT_SHA=${COMMIT_SHA} \
    REPO_INFO=https://github.com/Shopify/ingress-nginx.git \
    TAG=${TAG} \
    /build/build.sh

FROM gcr.io/google.com/cloudsdktool/cloud-sdk:371.0.0 as geoip_builder

ARG FREE_GEOIP_FILES
ARG PAID_GEOIP_FILES

COPY build/shopify/geoip.sh /

RUN --mount=type=secret,id=gcscredentials,required=true \
    gcloud auth activate-service-account --key-file=/run/secrets/gcscredentials && \
    FREE_GEOIP_FILES=${FREE_GEOIP_FILES} \
    PAID_GEOIP_FILES=${PAID_GEOIP_FILES} \
    /geoip.sh

FROM ${BASE_IMAGE}

ARG ARCH

COPY --from=go_builder /go/bin/${ARCH} bin/${ARCH}
COPY --from=geoip_builder geoip geoip

# Copyright 2015 The Kubernetes Authors. All rights reserved.
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

ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG VERSION
ARG COMMIT_SHA
ARG BUILD_ID=UNSET

LABEL org.opencontainers.image.title="NGINX Ingress Controller for Kubernetes"
LABEL org.opencontainers.image.documentation="https://kubernetes.github.io/ingress-nginx/"
LABEL org.opencontainers.image.source="https://github.com/kubernetes/ingress-nginx"
LABEL org.opencontainers.image.vendor="The Kubernetes Authors"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"

LABEL build_id="${BUILD_ID}"

WORKDIR  /etc/nginx

RUN apk update \
  && apk upgrade \
  && apk add --no-cache \
    diffutils \
  && rm -rf /var/cache/apk/*

COPY --chown=www-data:www-data etc /etc

COPY --chown=www-data:www-data bin/${TARGETARCH}/dbg /
COPY --chown=www-data:www-data bin/${TARGETARCH}/nginx-ingress-controller /
COPY --chown=www-data:www-data bin/${TARGETARCH}/wait-shutdown /

# Fix permission during the build to avoid issues at runtime
# with volumes (custom templates)
RUN bash -xeu -c ' \
  writeDirs=( \
    /etc/ingress-controller \
    /etc/ingress-controller/ssl \
    /etc/ingress-controller/auth \
    /var/log \
    /var/log/nginx \
  ); \
  for dir in "${writeDirs[@]}"; do \
    mkdir -p ${dir}; \
    chown -R www-data.www-data ${dir}; \
  done'

COPY geoip/*.gz /etc/nginx/geoip/
RUN gunzip -fk /etc/nginx/geoip/*.gz \
  && rm -rf /etc/nginx/geoip/*.gz \
  && chown -R www-data.www-data /etc/nginx/geoip

RUN apk add --no-cache libcap \
  && setcap    cap_net_bind_service=+ep /nginx-ingress-controller \
  && setcap -v cap_net_bind_service=+ep /nginx-ingress-controller \
  && setcap    cap_net_bind_service=+ep /usr/local/nginx/sbin/nginx \
  && setcap -v cap_net_bind_service=+ep /usr/local/nginx/sbin/nginx \
  && setcap    cap_net_bind_service=+ep /usr/bin/dumb-init \
  && setcap -v cap_net_bind_service=+ep /usr/bin/dumb-init \
  && apk del libcap

USER www-data

# Create symlinks to redirect nginx logs to stdout and stderr docker log collector
RUN  ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["/nginx-ingress-controller"]
