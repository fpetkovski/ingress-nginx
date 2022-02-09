### How to release a new base image
1. Make changes to `images/nginx`.
1. Bump version in `images/nginx/rootfs/VERSION`. The first three components of the version
should match the NGINX version being used. The last component is for Shopify versioning.
    - Note that bumping this on your branch will create a new image, it just won't be tagged.
1. Create a PR with your changes and merge the PR after getting it reviewed.
1. Wait for the image build to be complete in master.
1. Bump the image tag `$BASE_IMAGE` in `build/shopify/e2e.sh` to use new base image in e2e tests.
1. Bump `container.production.dockerfile.build_args.BASE_IMAGE` in `.shopify-build/shopify-slash-ingress-nginx-production-builder.yml` to use the new image in production.
1. Make a PR and make sure e2e tests run successfully with the new base image and then merge it.
