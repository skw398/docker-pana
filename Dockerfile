# Maintained manually against the pub.dev worker configuration.
FROM mirror.gcr.io/library/debian:13@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308

RUN test "$(dpkg --print-architecture)" = "amd64"

ENV DART_SDK=/opt/dart-sdk \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/home/pana/.pub-cache \
    PUB_ENVIRONMENT="bot.pub_dev.pub_worker" \
    CI="true" \
    NO_COLOR="true" \
    PANA_OPT_OUT_DARTDOC_SANITIZE_HTML="true"
ENV PATH="/opt/dart-sdk/bin:/opt/flutter/bin:/opt/pana/bin:/opt/webp/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 2000 pana \
    && useradd --uid 2000 --gid 2000 --create-home pana \
    && mkdir -p /opt/pana/bin /opt/webp/bin \
    && chown -R pana:pana /opt

USER pana
WORKDIR /opt/pana

RUN curl --fail --location --retry 3 \
        https://storage.googleapis.com/dart-archive/channels/stable/release/3.13.5/sdk/dartsdk-linux-x64-release.zip -o /tmp/dart.zip \
    && echo 'ea864bc64df30a6b8bdf30b2e32550f7717d9a890de8f40293aeabb924fe232b  /tmp/dart.zip' | sha256sum --check - \
    && unzip -q /tmp/dart.zip -d /opt && rm /tmp/dart.zip \
    && dart --disable-analytics \
    && mkdir -p /home/pana/config/dart-stable /home/pana/config/flutter-stable

RUN curl --fail --location --retry 3 \
        https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.7-stable.tar.xz -o /tmp/flutter.tar.xz \
    && echo 'af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230  /tmp/flutter.tar.xz' | sha256sum --check - \
    && tar --no-same-owner -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
    && flutter --no-version-check config --no-analytics --no-cli-animations \
    && flutter --no-version-check doctor

# Newer than pub.dev's 1.3.0 (CVE-2023-4863, CVE-2023-1999): 1.3.2 is the
# smallest release with both fixes, which keeps the difference from pub.dev
# minimal. pana decodes untrusted screenshots with these tools, and this image
# has no sandbox.
RUN curl --fail --location --retry 3 \
        https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.3.2-linux-x86-64.tar.gz -o /tmp/webp.tar.gz \
    && echo '71e8920e05bb2e62c47e6b2a7431007b80780b652e00952bcdcda32bf011c11c  /tmp/webp.tar.gz' | sha256sum --check - \
    && tar -xzf /tmp/webp.tar.gz --strip-components=2 -C /opt/webp/bin \
        libwebp-1.3.2-linux-x86-64/bin/cwebp libwebp-1.3.2-linux-x86-64/bin/dwebp \
        libwebp-1.3.2-linux-x86-64/bin/webpinfo libwebp-1.3.2-linux-x86-64/bin/gif2webp \
        libwebp-1.3.2-linux-x86-64/bin/webpmux \
    && rm /tmp/webp.tar.gz \
    && for tool in cwebp dwebp webpinfo gif2webp webpmux; do "$tool" -version || exit 1; done

# Keep pana's dependencies and SPDX scoring data aligned with the official lockfile.
# Match pub.dev's AOT execution and runtime core-lint loading.
COPY --chown=pana:pana runtime/ /opt/pana/
RUN dart pub get --enforce-lockfile \
    && dart compile exe --packages=.dart_tool/package_config.json \
        "$PUB_CACHE/hosted/pub.dev/pana-0.23.19/bin/pana.dart" -o bin/pana \
    && cp -R "$PUB_CACHE/hosted/pub.dev/pana-0.23.19/lib/src/third_party/spdx/licenses" /opt/pana/licenses

RUN dart pub unpack dartdoc:9.0.9 --output /opt \
    && mv /opt/dartdoc-9.0.9 /opt/dartdoc && cd /opt/dartdoc \
    && mkdir build && dart compile exe -o build/dartdoc bin/dartdoc.dart

# Distribution notices; separate from the SPDX data used for scoring.
RUN for package in "$PUB_CACHE"/hosted/pub.dev/*; do \
        if [ -f "$package/LICENSE" ]; then \
            mkdir -p "/opt/licenses/$(basename "$package")" \
            && cp "$package/LICENSE" "/opt/licenses/$(basename "$package")/LICENSE" || exit 1; \
        fi; \
    done
COPY licenses/ /usr/share/licenses/libwebp/

LABEL org.opencontainers.image.title="docker-pana" \
    dev.docker-pana.upstream.repository="https://github.com/dart-lang/pub-dev" \
    dev.docker-pana.dart="3.13.5" \
    dev.docker-pana.flutter="3.47.7" \
    dev.docker-pana.pana="0.23.19" \
    dev.docker-pana.dartdoc="9.0.9" \
    dev.docker-pana.webp="1.3.2"

WORKDIR /package
ENTRYPOINT ["pana", "--dart-sdk", "/opt/dart-sdk", "--flutter-sdk", "/opt/flutter", "--dart-config-home", "/home/pana/config/dart-stable", "--flutter-config-home", "/home/pana/config/flutter-stable", "--dartdoc-command", "/opt/dartdoc/build/dartdoc,--resources-dir,/opt/dartdoc/lib/resources", "--license-data", "/opt/pana/licenses", "--dartdoc-timeout", "1800", "--total-timeout", "3000"]
CMD ["/package"]
