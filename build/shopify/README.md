### How to release a new base image
1. Make changes to `images/nginx`.
1. Bump version in `build/shopify/BASE_VERSION`. The first three components of the version
should match the NGINX version being used. The last component is for Shopify versioning.
1. Create a PR with your changes and merge the PR after getting it reviewed.
1. Wait for the image build to be complete in master.
1. Bump the image tag `$BASE_IMAGE` in `build/shopify/e2e.sh` to use new base image in e2e tests.
1. Make a PR and make sure e2e tests run successfully with the new base image and then merge it.

### How to experiment with new base image in CI
You can also build and release new base image directly from your branches. To do so edit 
`.shopify-build/shopify-slash-ingress-nginx-production-builder.yml` and temporarily change the
value of `BUILD_CI_BASE_IMAGE` to `"1"`. DO NOT forget to rever that back to `"0"`.
