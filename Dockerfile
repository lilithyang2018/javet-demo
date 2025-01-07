FROM nexus3:5000/library/alpine:3.20.3

# proxy
ARG HTTP_PROXY=http://192.168.1.36:7890
ARG HTTPS_PROXY=http://192.168.1.36:7890

### install GNU libc
# see https://wiki.alpinelinux.org/wiki/Running_glibc_programs
# see https://github.com/sgerrand/alpine-pkg-glibc
ENV LANG=en_US.UTF-8
ARG ALPINE_GLIBC_PACKAGE_VERSION=2.29-r0

RUN apk add --no-cache libc6-compat bash

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
  && /usr/glibc-compat/sbin/ldconfig /lib /usr/glibc-compat/lib \
  && /usr/glibc-compat/bin/localedef --force --inputfile POSIX --charmap UTF-8 C.UTF-8 || true \
  && echo "export LANG=C.UTF-8" > /etc/profile.d/locale.sh \
  && rm \
    "/tmp/glibc-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-bin-$ALPINE_GLIBC_PACKAGE_VERSION.apk" \
    "/tmp/glibc-i18n-$ALPINE_GLIBC_PACKAGE_VERSION.apk"

ENV PATH="/usr/glibc-compat/bin:$PATH"

RUN echo $PATH \
    && ls -l /usr/glibc-compat/bin \
    && which ldd \
    && ldd --version

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

# Copy Java application files
COPY target/demo-0.0.1-SNAPSHOT.jar /demo.jar


# Entry point for the Java application
ENTRYPOINT ["java", "-jar", "demo.jar"]
