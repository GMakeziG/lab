FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132 AS extract

ARG CALIBRE_VERSION=9.14.0
ARG CALIBRE_SHA256=7f53a0863ed6d32407bc72053b966e39d5b64813f2592bd9c741504c01c0e7f3

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl xz-utils \
    && curl --fail --location --show-error \
      "https://download.calibre-ebook.com/${CALIBRE_VERSION}/calibre-${CALIBRE_VERSION}-x86_64.txz" \
      --output /tmp/calibre.txz \
    && echo "${CALIBRE_SHA256}  /tmp/calibre.txz" | sha256sum --check --strict \
    && mkdir -p /opt/calibre \
    && tar --extract --xz --file /tmp/calibre.txz --directory /opt/calibre \
    && rm -f \
      /opt/calibre/calibre \
      /opt/calibre/calibre-debug \
      /opt/calibre/calibre-portable \
      /opt/calibre/calibre-smtp \
      /opt/calibre/ebook-edit \
      /opt/calibre/ebook-viewer \
      /opt/calibre/lrfviewer \
      /opt/calibre/lib/libQt6WaylandClient.so.6 \
      /opt/calibre/lib/libQt6XcbQpa.so.6 \
      /opt/calibre/plugins/egldeviceintegrations/libqeglfs-x11-integration.so \
      /opt/calibre/plugins/platforms/libqwayland.so \
      /opt/calibre/plugins/platforms/libqxcb.so \
    && rm -rf \
      /opt/calibre/plugins/wayland-decoration-client \
      /opt/calibre/plugins/wayland-graphics-integration-client \
      /opt/calibre/plugins/wayland-shell-integration \
      /opt/calibre/plugins/xcbglintegrations

FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

# QtGui imports the GLVND EGL ABI even with the offscreen backend. Extract only
# that ABI library, avoiding libegl1's Mesa/X11/Wayland provider tree.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates libfontconfig1 libglvnd0 libopengl0 libx11-6 libxkbcommon0 \
    && cd /tmp \
    && apt-get download libegl1 libglx0 \
    && dpkg-deb --extract libegl1_*.deb / \
    && dpkg-deb --extract libglx0_*.deb / \
    && rm -f libegl1_*.deb libglx0_*.deb \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 calibre \
    && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /config --shell /usr/sbin/nologin calibre \
    && mkdir -p /config /library \
    && chown 10001:10001 /config /library

COPY --from=extract /opt/calibre /opt/calibre
COPY entrypoint.sh /usr/local/bin/calibre-entrypoint
RUN chmod 0555 /usr/local/bin/calibre-entrypoint

ENV PATH="/opt/calibre:${PATH}" \
    CALIBRE_CONFIG_DIRECTORY=/config \
    QT_QPA_PLATFORM=offscreen

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/calibre-entrypoint"]
CMD ["--listen-on", "0.0.0.0", "--port", "8080", "--enable-auth", "--userdb", "/config/users.sqlite", "/library"]
