# Minimal toolbox image for SRPS (defaults to dry-run)
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

# Create non-root user with passwordless sudo to satisfy installer checks
RUN apt-get update -qq \
    && apt-get install -y -qq sudo bash ca-certificates git curl \
    && useradd -m -s /bin/bash srps \
    && echo "srps ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/srps \
    && chmod 0440 /etc/sudoers.d/srps

USER srps
WORKDIR /home/srps/app

COPY install.sh verify.sh README.md ./

# Default to plan mode to avoid accidental system changes inside container
ENTRYPOINT ["/bin/bash", "./install.sh"]
CMD ["--plan"]

# Usage examples:
#   docker run --rm -it ghcr.io/you/srps-tools            # dry-run/plan
#   docker run --rm -it --privileged -v /:/host ghcr.io/you/srps-tools --plan
#   (Not recommended to apply changes to host; if you do, bind-mount and review flags carefully.)
