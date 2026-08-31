# Ninjatronics Calibre server image

This image contains the official Calibre 9.14.0 Linux binary on a digest-pinned
Debian trixie-slim base. The build verifies the upstream archive SHA-256 and
removes desktop launchers plus XCB/Wayland platform plugins. It runs only the
headless content server as UID/GID 10001 on port 8080. The official server's
cover-rendering code imports QtGui and therefore retains the minimal GLVND,
fontconfig, and libX11 client ABI libraries; no display server or desktop stack
is installed or started.

Build and publish it from this directory:

```sh
make build
docker run --rm ghcr.io/ninjatronics/calibre-server:9.14.0 calibre-server --version
make push
```

The preferred path is the published GHCR image. If registry credentials are
not available, load the exact locally built tag into k3s on the pinned node:

```sh
docker save ghcr.io/ninjatronics/calibre-server:9.14.0 | \
  ssh niner sudo k3s ctr images import -
ssh niner sudo k3s ctr images list | grep calibre-server
```

The production Deployment uses `IfNotPresent`, so containerd will use that
node-local image. GHCR publishing should replace this operational workaround;
after publishing, pin the Deployment to the registry manifest digest.
