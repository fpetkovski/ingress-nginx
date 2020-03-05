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

echo "--- docker build"
ARCH="amd64"
TAG=${PIPA_APP_SHA:-latest}
REGISTRY=${PIPA_DOCKER_REGISTRY}/shopify-docker-images/apps/production ARCH=${ARCH} TAG=${TAG} make build container

IMAGE_NAME="shopify-docker-images/apps/production/nginx-ingress-controller-${ARCH}"
echo "--- pushing ${PIPA_DOCKER_REGISTRY}/${IMAGE_NAME}:${TAG}"
pipa image push -r "${PIPA_DOCKER_REGISTRY}" -n "${IMAGE_NAME}" -t "${TAG}"
