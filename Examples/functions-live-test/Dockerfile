# Multi-stage build for the relay-function OCI Function.
# Build context is this directory (Examples/functions-live-test); the SDK is
# fetched from GitHub per Package.swift, so the surrounding repo is not needed.

FROM swift:6.2 AS build
WORKDIR /src
COPY . .
RUN swift build -c release --product relay-function --static-swift-stdlib
RUN install -Dm755 "$(swift build -c release --product relay-function --show-bin-path)/relay-function" /out/relay-function

FROM ubuntu:24.04
# --static-swift-stdlib bundles the Swift stdlib but NOT system C libs. A function
# that calls OCI services goes through Foundation's URLSession, which on Linux uses
# libcurl, so the runtime image needs libcurl + a CA trust store (and libxml2).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libxml2 tzdata \
 && (apt-get install -y --no-install-recommends libcurl4t64 || apt-get install -y --no-install-recommends libcurl4) \
 && rm -rf /var/lib/apt/lists/*
# OCI Functions require a non-root user (uid/gid 1000). ubuntu:24.04 ships a
# default `ubuntu` user at 1000, so remove it before creating `fn`.
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd --gid 1000 fn \
 && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin fn
COPY --from=build /out/relay-function /function/relay-function
USER fn
ENTRYPOINT ["/function/relay-function"]
