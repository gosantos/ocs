FROM debian:trixie-slim

# Pin a specific opencode release with:
#   docker build --build-arg OPENCODE_VERSION=2.2.6 -t opencode-sandbox:latest .
ARG OPENCODE_VERSION=

# Runtime dependencies only: opencode is a native binary, Node is not needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates curl ripgrep tar xz-utils \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/locale /var/cache/apt /tmp/*

# uid/gid 1001 so the host can `docker cp` files owned by `dev`.
RUN useradd -u 1001 -m -s /bin/bash dev \
    && mkdir -p /work && chown -R dev:dev /home/dev /work

USER dev
ENV HOME=/home/dev
# The official v2 installer resolves the right linux-arm64/x64 glibc binary.
RUN if [ -n "$OPENCODE_VERSION" ]; then \
      curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path --version "$OPENCODE_VERSION"; \
    else \
      curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path; \
    fi \
    && mkdir -p /home/dev/.local/share/opencode /home/dev/.config/opencode

USER root
RUN ln -sf /home/dev/.opencode/bin/opencode /usr/local/bin/opencode

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER dev
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
