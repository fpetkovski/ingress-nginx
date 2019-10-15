#!/bin/bash

# Copyright 2018 The Kubernetes Authors.
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

if ! [ -z "$DEBUG" ]; then
	set -x
fi

set -o errexit
set -o nounset
set -o pipefail

_term() {
  echo "Test aborted via SIGTERM - was the CI instance preempted?"
  exit 1
}
trap _term SIGTERM

pretty_title()
{
  TITLE=$1
  echo ""
  echo ""
  echo "========== ${TITLE} =========="
  echo ""
}

docker_build()
{
  IMAGE=$1
  DIR=$2
  FILE=${3:-Dockerfile}
  ARGS=${4:-}

  if [ -z $ARGS ]
  then
    docker build --network=host -t ${IMAGE} -f ${DIR}/${FILE} ${DIR}
  else
    docker build --network=host --build-arg ${ARGS} -t ${IMAGE} -f ${DIR}/${FILE} ${DIR}
  fi
}

export TAG=dev
export ARCH=amd64
export REGISTRY=ingress-controller

pretty_title "Building controller binary and image"
DEV_IMAGE=${REGISTRY}/nginx-ingress-controller:${TAG}
docker_build "${DEV_IMAGE}" "." "Dockerfile.shopify-build" "APP_SHA=e2e"

pretty_title "Building e2e test binary"
build/run-in-docker.sh make e2e-test-binary

# NOTE(elvinefendi): all of the following can be done withing docker using build/run-in-docker.sh too if
# we had docker executable in the image build/run-in-docker.sh uses. The benefit of running all these
# in that container is that then we could use make build container like in
# https://github.com/Shopify/ingress-nginx/blob/fcbcad5f6994201b9e97d4e621c5f6fa10989f2e/test/e2e/run.sh#L65
# When this is done we should also be able to use images/fastcgi-helloserver/rootfs/Dockerfile and
# images/httpbin/rootfs/Dockerfile as is from upstream.

pretty_title "Building e2e test image"
cp test/e2e/e2e.test test/e2e-image
cp test/e2e/wait-for-nginx.sh test/e2e-image
cp -r deploy/cloud-generic test/e2e-image
cp -r deploy/cluster-wide test/e2e-image
docker_build "nginx-ingress-controller:e2e" "test/e2e-image"

pretty_title "Building fastcgi-helloserver binary"
build/run-in-docker.sh \
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo \
    -ldflags \"-s -w\" -o images/fastcgi-helloserver/rootfs/fastcgi-helloserver k8s.io/ingress-nginx/images/fastcgi-helloserver/...
pretty_title "Building fastcgi-helloserver image"
docker_build "${REGISTRY}/fastcgi-helloserver:${TAG}" "images/fastcgi-helloserver/rootfs"

pretty_title "Building httpbin image"
docker_build "${REGISTRY}/httpbin:${TAG}" "images/httpbin/rootfs"

pretty_title "Running e2e tests"
build/run-in-docker.sh make e2e-test
