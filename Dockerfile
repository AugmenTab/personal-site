# Haskell build environment for the personal site.
#
# Base image: the toolchain Brigid itself is developed and tested against
# (GHC 9.10.3, Stack 3.7.1, Debian trixie). Pinned by tag *and* multi-arch
# index digest so a re-pushed tag cannot silently change the toolchain.
FROM ghcr.io/flipstone/haskell-tools:debian-ghc-9.10.3-1e1d10c@sha256:7cd1e197eb25e86dc0878ad1572ea5d2675c565226c3a199f5570d4b55c9e5ad

# Brigid's core library depends on the `libphonenumber` Haskell binding, which
# links against these system libraries. They are not present in the base image.
RUN apt-get update \
 && apt-get install -qq -y --no-install-recommends libphonenumber-dev libprotobuf-dev \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Stack's global cache (snapshot + extra-dep builds) lives in a named volume
# mounted here; see compose.yaml.
ENV STACK_ROOT=/stack-root

COPY docker/entrypoint.sh /usr/local/bin/site-entrypoint

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/site-entrypoint"]
CMD ["docker/build-site.sh"]
