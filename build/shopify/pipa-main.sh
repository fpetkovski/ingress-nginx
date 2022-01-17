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

#########################################################################################

echo "--- docker build base Nginx image"

BASE_TAG="$(cat build/shopify/BASE_VERSION)"
BASE_IMAGE_PREFIX="shopify-docker-images/apps/production"
if [ "${BUILDKITE_BRANCH}" != "master" ] && [ ${BUILD_CI_BASE_IMAGE} == "1" ]; then
  BASE_TAG=${PIPA_APP_SHA:-latest}
  BASE_IMAGE_PREFIX="shopify-docker-images/apps/ci"
fi
BASE_IMAGE="${PIPA_DOCKER_REGISTRY}/${BASE_IMAGE_PREFIX}/nginx:${BASE_TAG}"

if [ "${BUILDKITE_BRANCH}" == "master" ] || [ ${BUILD_CI_BASE_IMAGE} == "1" ]; then
  if pipa image exists -r "$PIPA_DOCKER_REGISTRY" -n "${BASE_IMAGE_PREFIX}/nginx" -t "${BASE_TAG}" --remote; then
    echo "base image $BASE_IMAGE exists"
  else
    REGISTRY=${PIPA_DOCKER_REGISTRY}/${BASE_IMAGE_PREFIX} TAG=${BASE_TAG} make -C images/nginx container

    pipa image push -r "${PIPA_DOCKER_REGISTRY}" -n "${BASE_IMAGE_PREFIX}/nginx" -t "${BASE_TAG}"
  fi
else
  echo "skipping base image build"
fi

#########################################################################################

curr_dir="$(dirname "$0")"
"$curr_dir/geoip.sh"

#########################################################################################

echo "--- docker build controller image"
TAG=${PIPA_APP_SHA:-latest}
IMAGE_PREFIX="shopify-docker-images/apps/ci"
if [ "${BUILDKITE_BRANCH}" == "master" ]; then
  IMAGE_PREFIX="shopify-docker-images/apps/production"
fi
REGISTRY=${PIPA_DOCKER_REGISTRY}/${IMAGE_PREFIX} BASE_IMAGE=${BASE_IMAGE} ARCH=amd64 TAG=${TAG} make build image

INTERMEDIATE_IMAGE_NAME="${IMAGE_PREFIX}/controller"
IMAGE_NAME="${IMAGE_PREFIX}/ingress-nginx"

docker tag "${PIPA_DOCKER_REGISTRY}/${INTERMEDIATE_IMAGE_NAME}:${TAG}" "${PIPA_DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "--- pushing ${PIPA_DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
pipa image push -r "${PIPA_DOCKER_REGISTRY}" -n "${IMAGE_NAME}" -t "${TAG}"
