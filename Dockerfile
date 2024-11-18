FROM alpine:3.20.3

# proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY

# Node.js setup
ENV NODE_VERSION 18.20.4
ENV YARN_VERSION 1.22.19

# Install Node.js
# see https://github.com/nodejs/docker-node/blob/main/18/alpine3.20/Dockerfile
RUN apk add --no-cache \
        libstdc++ \
    && apk add --no-cache --virtual .build-deps \
        curl \
    && ARCH= OPENSSL_ARCH='linux*' && alpineArch="$(apk --print-arch)" \
      && case "${alpineArch##*-}" in \
        x86_64) ARCH='x64' CHECKSUM="ac4fe3bef38d5e4ecf172b46c8af1f346904afd9788ce12919e3696f601e191e" OPENSSL_ARCH=linux-x86_64;; \
        x86) OPENSSL_ARCH=linux-elf;; \
        aarch64) OPENSSL_ARCH=linux-aarch64;; \
        arm*) OPENSSL_ARCH=linux-armv4;; \
        ppc64le) OPENSSL_ARCH=linux-ppc64le;; \
        s390x) OPENSSL_ARCH=linux-s390x;; \
        *) ;; \
      esac \
  && if [ -n "${CHECKSUM}" ]; then \
    set -eu; \
    curl -fsSLO --compressed "https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz"; \
    echo "$CHECKSUM  node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" | sha256sum -c - \
      && tar -xJf "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
      && ln -s /usr/local/bin/node /usr/local/bin/nodejs; \
  else \
    echo "Building from source" \
    # backup build
    && apk add --no-cache --virtual .build-deps-full \
        binutils-gold \
        g++ \
        gcc \
        gnupg \
        libgcc \
        linux-headers \
        make \
        python3 \
        py-setuptools \
    # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
    && export GNUPGHOME="$(mktemp -d)" \
    # gpg keys listed at https://github.com/nodejs/node#release-keys
    && for key in \
      4ED778F539E3634C779C87C6D7062848A1AB005C \
      141F07595B7B3FFE74309A937405533BE57C7D57 \
      74F12602B6F1C4E913FAA37AD3A89613643B6201 \
      DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
      61FC681DFB92A079F1685E77973F295594EC4689 \
      8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
      C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
      890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
      C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
      108F52B48DB57BB0CC439B2997B01419BD92F80A \
      A363A499291CBBC940DD62E41F10027AF002F8B0 \
      CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
    ; do \
      gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
      gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
    done \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
    && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xf "node-v$NODE_VERSION.tar.xz" \
    && cd "node-v$NODE_VERSION" \
    && ./configure \
    && make -j$(getconf _NPROCESSORS_ONLN) V= \
    && make install \
    && apk del .build-deps-full \
    && cd .. \
    && rm -Rf "node-v$NODE_VERSION" \
    && rm "node-v$NODE_VERSION.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt; \
  fi \
  && rm -f "node-v$NODE_VERSION-linux-$ARCH-musl.tar.xz" \
  # Remove unused OpenSSL headers to save ~34MB. See this NodeJS issue: https://github.com/nodejs/node/issues/46451
  && find /usr/local/include/node/openssl/archs -mindepth 1 -maxdepth 1 ! -name "$OPENSSL_ARCH" -exec rm -rf {} \; \
  && apk del .build-deps \
  # smoke tests
  && node --version \
  && npm --version

# Install Yarn
# see https://github.com/nodejs/docker-node/blob/main/18/alpine3.20/Dockerfile
RUN apk add --no-cache --virtual .build-deps-yarn curl gnupg tar \
  # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
  && export GNUPGHOME="$(mktemp -d)" \
  && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
  ; do \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
  done \
  && if [ -n "$HTTP_PROXY" ]; then export http_proxy=$HTTP_PROXY; fi \
  && if [ -n "$HTTPS_PROXY" ]; then export https_proxy=$HTTPS_PROXY; fi \
  && curl -fsSLO --compressed "https://github.com/yarnpkg/yarn/releases/download/v$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && curl -fsSLO --compressed "https://github.com/yarnpkg/yarn/releases/download/v$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
  && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && gpgconf --kill all \
  && rm -rf "$GNUPGHOME" \
  && mkdir -p /opt \
  && chmod -R 755 /opt \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ --no-same-permissions --no-same-owner \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
  && apk del .build-deps-yarn \
  # smoke test
  && yarn --version \
  && rm -rf /tmp/*

# Install JRE
# see https://github.com/adoptium/containers/blob/d7a5038edcd8ab08b0babaeae09d0c097453a023/17/jre/alpine/Dockerfile
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH=$JAVA_HOME/bin:$PATH

# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

RUN set -eux; \
    apk add --no-cache \
        # java.lang.UnsatisfiedLinkError: libfontmanager.so: libfreetype.so.6: cannot open shared object file: No such file or directory
        # java.lang.NoClassDefFoundError: Could not initialize class sun.awt.X11FontManager
        # https://github.com/docker-library/openjdk/pull/235#issuecomment-424466077
        fontconfig ttf-dejavu \
        # gnupg required to verify the signature
        gnupg \
        # utilities for keeping Alpine and OpenJDK CA certificates in sync
        # https://github.com/adoptium/containers/issues/293
        ca-certificates p11-kit-trust \
        # locales ensures proper character encoding and locale-specific behaviors using en_US.UTF-8
        musl-locales musl-locales-lang \
        tzdata \
        # Contains `csplit` used for splitting multiple certificates in one file to multiple files, since keytool can
        # only import one at a time.
        coreutils \
        # Needed to extract CN and generate aliases for certificates
        openssl \
    ; \
    rm -rf /var/cache/apk/*

ENV JAVA_VERSION=jdk-17.0.13+11

RUN set -eux; \
    apk add --no-cache \
        gcompat \
        libstdc++ \
    ; \
    ARCH="$(apk --print-arch)"; \
    case "${ARCH}" in \
       x86_64) \
         ESUM='7a2df4e2f86eca649af1e17d990ab8e354cb6dee389606025b9d05f75623c388'; \
         BINARY_URL='https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jre_x64_alpine-linux_hotspot_17.0.13_11.tar.gz'; \
         ;; \
       *) \
         echo "Unsupported arch: ${ARCH}"; \
         exit 1; \
         ;; \
    esac; \
    if [ -n "$HTTP_PROXY" ]; then export http_proxy=$HTTP_PROXY; fi; \
    if [ -n "$HTTPS_PROXY" ]; then export https_proxy=$HTTPS_PROXY; fi; \
    wget -O /tmp/openjdk.tar.gz ${BINARY_URL}; \
    wget -O /tmp/openjdk.tar.gz.sig ${BINARY_URL}.sig; \
    export GNUPGHOME="$(mktemp -d)"; \
    # gpg: key 843C48A565F8F04B: "Adoptium GPG Key (DEB/RPM Signing Key) <temurin-dev@eclipse.org>" imported
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 3B04D753C9050D9A5D343F39843C48A565F8F04B; \
    gpg --batch --verify /tmp/openjdk.tar.gz.sig /tmp/openjdk.tar.gz; \
    rm -r "${GNUPGHOME}" /tmp/openjdk.tar.gz.sig; \
    echo "${ESUM} */tmp/openjdk.tar.gz" | sha256sum -c -; \
    mkdir -p "$JAVA_HOME"; \
    tar --extract \
        --file /tmp/openjdk.tar.gz \
        --directory "$JAVA_HOME" \
        --strip-components 1 \
        --no-same-owner \
    ; \
    rm -f /tmp/openjdk.tar.gz ${JAVA_HOME}/lib/src.zip;

RUN set -eux; \
    echo "Verifying install ..."; \
    echo "java --version"; java --version; \
    echo "Complete."

### install GNU libc
# see https://wiki.alpinelinux.org/wiki/Running_glibc_programs
# see https://github.com/sgerrand/alpine-pkg-glibc
ENV LANG=en_US.UTF-8
ARG ALPINE_GLIBC_PACKAGE_VERSION=2.29-r0

RUN if [ -n "$HTTP_PROXY" ]; then export http_proxy=$HTTP_PROXY; fi \
  && if [ -n "$HTTPS_PROXY" ]; then export https_proxy=$HTTPS_PROXY; fi \
  && wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub \
  && wget -P /tmp \
    https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$ALPINE_GLIBC_PACKAGE_VERSION/glibc-$ALPINE_GLIBC_PACKAGE_VERSION.apk \
    https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$ALPINE_GLIBC_PACKAGE_VERSION/glibc-bin-$ALPINE_GLIBC_PACKAGE_VERSION.apk \
    https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$ALPINE_GLIBC_PACKAGE_VERSION/glibc-i18n-$ALPINE_GLIBC_PACKAGE_VERSION.apk \
  && apk add --no-cache --force-overwrite \
    "/tmp/glibc-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-bin-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-i18n-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
  && rm /etc/apk/keys/sgerrand.rsa.pub \
  && /usr/glibc-compat/bin/localedef --force --inputfile POSIX --charmap UTF-8 C.UTF-8 || true \
  && echo "export LANG=C.UTF-8" > /etc/profile.d/locale.sh \
  && rm \
    "/tmp/glibc-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-bin-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-i18n-$ALPINE_GLIBC_PACKAGE_VERSION.apk"

# Copy Java application files
COPY target/demo-0.0.1-SNAPSHOT.jar /demo.jar


# Entry point for the Java application
ENTRYPOINT ["java", "-jar", "demo.jar"]
