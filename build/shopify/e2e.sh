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

# TODO(elvinefendi): bake `make` into k8s-ci machines
echo "Installing make"
while true; do
  sudo lsof /var/lib/dpkg/lock-frontend > /dev/null && (echo "Waiting for apt/dpkg to finish..."; sleep 10) || break
done
sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y make

# Use 1.0.0-dev to make sure we use the latest configuration in the helm template
export TAG=1.0.0-dev
export ARCH=amd64
export REGISTRY=ingress-controller
# Notice that here we deliberately do not read the tag from images/nginx/rootfs/VERSION to avoid
# CI failures when we release a new base image.
export BASE_IMAGE="gcr.io/shopify-docker-images/apps/production/nginx:1.19.10.1"

# Mock file and directory to prevent e2e docker build from failing due to geoip databases copied during production build
GEOIP_DB_DIR="$PWD/rootfs/geoip"
mkdir -p "${GEOIP_DB_DIR}"
touch "${GEOIP_DB_DIR}/file.txt"
tar -czvf "${GEOIP_DB_DIR}/file.gz" "${GEOIP_DB_DIR}/file.txt"

# pull the base image into local repository
# so that docker ... does not run into GCR auth issue.
gcloud docker -- pull ${BASE_IMAGE}

echo "[dev-env] building container"
make build image
make -C test/e2e-image
make -C images/fastcgi-helloserver/ container
make -C images/echo/ container
make -C images/httpbin/ container

echo "[dev-env] running e2e tests..."
make e2e-test
