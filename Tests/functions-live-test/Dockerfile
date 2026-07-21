# Multi-stage build for the relay-function OCI Function.
# Build context is this directory; the SDK is fetched from GitHub per
# Package.swift, so the surrounding repo is not needed.
#
# The runtime stage uses `swift:<version>-slim`, the official Swift runtime
# image: it already carries the Swift runtime libraries plus libcurl, libxml2,
# and ca-certificates, which Foundation's URLSession needs on Linux. Keep the
# builder and runtime tags on the SAME version — a slim image only runs
# binaries built by its matching toolchain.

FROM swift:6.2 AS build
WORKDIR /src
COPY . .
RUN swift build -c release --product relay-function
RUN install -Dm755 "$(swift build -c release --product relay-function --show-bin-path)/relay-function" /out/relay-function

FROM swift:6.2-slim
# OCI Functions require a non-root user (uid/gid 1000). The slim image is
# Ubuntu 24.04-based and ships a default `ubuntu` user at 1000, so remove it
# before creating `fn`.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd --gid 1000 fn \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin fn
COPY --from=build /out/relay-function /function/relay-function
USER fn
ENTRYPOINT ["/function/relay-function"]
