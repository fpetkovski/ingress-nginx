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

echo "--- downloading geoip databases"
IFS=','; free_urls=($FREE_GEOIP_FILES)
IFS=','; paid_urls=($PAID_GEOIP_FILES)
urls=()

GEOIP_DB_DIR="$PWD/rootfs/geoip"
mkdir "${GEOIP_DB_DIR}"

for url in "${free_urls[@]}"; do urls+=("gs://shopify-mmdb-free/$url.gz"); done
for url in "${paid_urls[@]}"; do urls+=("gs://shopify-mmdb-licensed/$url.gz"); done
for url in "${urls[@]}"; do echo "$url"; done | gsutil -m cp -I "${GEOIP_DB_DIR}"

echo "--- docker build"
ARCH="amd64"
TAG=${PIPA_APP_SHA:-latest}
REGISTRY=${PIPA_DOCKER_REGISTRY}/shopify-docker-images/apps/production ARCH=${ARCH} TAG=${TAG} make build container

INTERMEDIATE_IMAGE_NAME="shopify-docker-images/apps/production/nginx-ingress-controller-${ARCH}"
IMAGE_NAME="shopify-docker-images/apps/production/ingress-nginx"

docker tag "${PIPA_DOCKER_REGISTRY}/${INTERMEDIATE_IMAGE_NAME}:${TAG}" "${PIPA_DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "--- pushing ${PIPA_DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
pipa image push -r "${PIPA_DOCKER_REGISTRY}" -n "${IMAGE_NAME}" -t "${TAG}"
