FROM alpine:3.21.3

# renovate: datasource=github-releases depName=helm-unittest/helm-unittest
ARG HELM_UNITTEST_VERSION=v0.7.1

RUN apk add --no-cache helm git

RUN helm plugin install https://github.com/helm-unittest/helm-unittest --version ${HELM_UNITTEST_VERSION}
