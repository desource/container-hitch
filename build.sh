#!/usr/bin/env bash

set -e

ACBUILD=${ACBUILD:-acbuild}
BASE=${BASE:-desource.net}

LIBRESSL_VERSION=2.3.3
LIBRESSL_SHA256=76733166187cc8587e0ebe1e83965ef257262a1a676a36806edd3b6d51b50aa9

HITCH_VERSION=1.1.1


function build_hitch() {
    rm -rf bin;

    cat <<EOF | docker build --pull -t "hitch-build" -
FROM gliderlabs/alpine:edge

RUN apk add --update \
  curl \
  tar \
  gcc \
  make \
  git \
  autoconf \
  automake \
  libtool \
  perl \
  linux-headers \
  libc-dev \
  libev-dev

WORKDIR /tmp
RUN \
  mkdir -p /tmp/libressl && \
  curl -OL http://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-$LIBRESSL_VERSION.tar.gz && \
  echo "$LIBRESSL_SHA256  libressl-$LIBRESSL_VERSION.tar.gz" | sha256sum -c && \
  tar -C /tmp/libressl --strip-components 1 -xf libressl-$LIBRESSL_VERSION.tar.gz

WORKDIR /tmp/libressl/build
RUN \
  ../configure --prefix=/usr && \
  make && \
  make install


WORKDIR /tmp
RUN \
  mkdir -p /tmp/hitch && \
  curl -OL https://github.com/varnish/hitch/archive/hitch-$HITCH_VERSION.tar.gz && \
  tar -C /tmp/hitch --strip-components 1 -xf hitch-$HITCH_VERSION.tar.gz

WORKDIR /tmp/hitch
RUN \
  ./bootstrap && \
  ./configure \
     --with-rst2man=/bin/true \
     LIBS=-lcrypto \
     LDFLAGS=-static && \
  make

EOF

    mkdir -p bin

    docker export $(docker run -d hitch-build echo "extract hitch") | \
        tar -xf - -C bin --strip-components=3 tmp/hitch/src/hitch    
}

build_docker() {
    docker build -t hitch:$HITCH_VERSION -f Dockerfile .
}

build_aci() {

    mkdir -p build/hitch

    $ACBUILD --debug begin
    trap "{ export EXT=$?; $ACBUILD --debug end && exit $EXT; }" EXIT

    $ACBUILD --debug set-name $BASE/hitch
    $ACBUILD --debug label add version $HITCH_VERSION
    $ACBUILD --debug copy bin/hitch   /bin/hitch
    $ACBUILD --debug set-exec -- /bin/hitch
    $ACBUILD --debug write build/hitch/$HITCH_VERSION-linux-amd64.aci --overwrite

    gpg --armor --yes --passphrase="$GPG_PASSWORD" \
        --output build/hitch/$HITCH_VERSION-linux-amd64.aci.asc \
        --detach-sig ./build/hitch/$HITCH_VERSION-linux-amd64.aci

}

build_hitch
build_docker
build_aci
