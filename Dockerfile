# build the executables
FROM golang:1.13.1-stretch AS builder
WORKDIR /go/src/k8s.io/ingress-nginx
COPY . /go/src/k8s.io/ingress-nginx
ARG APP_SHA
RUN GIT_COMMIT=${APP_SHA} ARCH=amd64 make build


# build the production image, the rest should resemble https://github.com/kubernetes/ingress-nginx/blob/master/rootfs/Dockerfile

# based on the image built in https://github.com/kubernetes/ingress-nginx/tree/master/images/nginx
FROM quay.io/kubernetes-ingress-controller/nginx-amd64:daf8634acf839708722cffc67a62e9316a2771c6

# copy the executables built in the previous stage
COPY --from=builder /go/src/k8s.io/ingress-nginx/bin/amd64/nginx-ingress-controller /nginx-ingress-controller
COPY --from=builder /go/src/k8s.io/ingress-nginx/bin/amd64/dbg /dbg
COPY --from=builder /go/src/k8s.io/ingress-nginx/bin/amd64/wait-shutdown /wait-shutdown

WORKDIR  /etc/nginx

RUN clean-install \
  diffutils \
  libcap2-bin

COPY rootfs/ /

RUN cp /usr/local/openresty/nginx/conf/mime.types /etc/nginx/mime.types \
 && cp /usr/local/openresty/nginx/conf/fastcgi_params /etc/nginx/fastcgi_params
RUN ln -s /usr/local/openresty/nginx/modules /etc/nginx/modules

# Fix permission during the build to avoid issues at runtime
# with volumes (custom templates)
RUN bash -eu -c ' \
  writeDirs=( \
    /etc/nginx \
    /etc/ingress-controller/ssl \
    /etc/ingress-controller/auth \
    /var/log \
    /var/log/nginx \
    /tmp \
  ); \
  for dir in "${writeDirs[@]}"; do \
    mkdir -p ${dir}; \
    chown -R www-data.www-data ${dir}; \
  done'

RUN  setcap    cap_net_bind_service=+ep /nginx-ingress-controller \
  && setcap -v cap_net_bind_service=+ep /nginx-ingress-controller

RUN  setcap    cap_net_bind_service=+ep /usr/local/openresty/nginx/sbin/nginx \
  && setcap -v cap_net_bind_service=+ep /usr/local/openresty/nginx/sbin/nginx

USER www-data

# Create symlinks to redirect nginx logs to stdout and stderr docker log collector
RUN  ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
  && ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log \
  && ln -s /usr/local/openresty/nginx/logs/* /var/log/nginx

ENTRYPOINT ["/usr/bin/dumb-init", "--"]

CMD ["/nginx-ingress-controller"]
