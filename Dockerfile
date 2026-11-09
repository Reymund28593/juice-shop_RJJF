# syntax=docker/dockerfile:1.7
# Based on the upstream OWASP Juice Shop Dockerfile (hardening steps kept). Differences:
#  - base images AND all npm packages come from Artifactory (no direct internet access during the build)
#  - the npm registry + token are mounted as a BuildKit secret, never stored in an image layer
#  - build metadata labels (commit, date, build number)

ARG REGISTRY
ARG DOCKER_VIRTUAL=juice-docker-virtual
# Docker Hub official images may need the "library/" prefix here: .../library/node:24
ARG NODE_IMAGE=${REGISTRY}/${DOCKER_VIRTUAL}/node:24
# distroless comes from a gcr.io remote repo that is part of the docker virtual repo
ARG RUNTIME_IMAGE=${REGISTRY}/${DOCKER_VIRTUAL}/distroless/nodejs24-debian13

# ---------- Stage 1: Installer ----------
FROM ${NODE_IMAGE} AS installer

WORKDIR /juice-shop

# The complete source must be present BEFORE "npm install": Juice Shop's postinstall script
# builds the frontend and the server (cd frontend && npm install && npm run build:frontend ...).
COPY . .

RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install -g typescript@^6.0.3
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install --omit=dev
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm dedupe --omit=dev

# Cleanup and permissions (as in upstream)
RUN rm -rf frontend/node_modules
RUN rm -rf frontend/.angular
RUN rm -rf frontend/src/assets
RUN mkdir logs
RUN chown -R 65532 logs
RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/
RUN chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/
RUN rm ftp/legal.md || true
RUN rm i18n/*.json || true

# Application SBOM (CycloneDX) from the project itself
ARG CYCLONEDX_NPM_VERSION='^2.0.0||^3.0.0||^4.0.0'
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm install -g @cyclonedx/cyclonedx-npm@"$CYCLONEDX_NPM_VERSION"
RUN npm run sbom

# ---------- Stage 2: Runtime (Distroless) ----------
FROM ${RUNTIME_IMAGE}

ARG BUILD_DATE
ARG VCS_REF
ARG BUILD_NUMBER

LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
      org.opencontainers.image.title="OWASP Juice Shop" \
      org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
      org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
      org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
      org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="20.3.0" \
      org.opencontainers.image.url="https://owasp-juice.shop" \
      org.opencontainers.image.source="https://github.com/Reymund28593/juice-shop_RJJF" \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.created=$BUILD_DATE \
      com.jfrog.build-number=$BUILD_NUMBER \
      com.jfrog.pipeline="secure-juice-shop"

WORKDIR /juice-shop

COPY --from=installer --chown=65532:0 /juice-shop .

USER 65532
EXPOSE 3000

CMD ["/juice-shop/build/app.js"]
