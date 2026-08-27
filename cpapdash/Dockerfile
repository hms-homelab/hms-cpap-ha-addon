# CpapDash as a Home Assistant add-on.
#
# FROM the published multi-arch image rather than building CpapDash here. That
# image is a C++ service plus an Angular bundle; compiling it inside the
# Supervisor's builder on a Pi is not an install, it is an afternoon. The base is
# an OCI index covering linux/amd64 and linux/arm64, so one FROM serves both
# architectures this add-on declares.
#
# KEEP THIS TAG IN STEP WITH `version:` IN config.yaml. They are what the user
# sees and what they actually get, and nothing checks that they agree.
#
# THE TAG MUST BE A RELEASE THAT CONTAINS SDD-021, which 5.0.5 is the first to
# be. Anything earlier serves <base href="/"> no matter what X-Ingress-Path says,
# so the page loads through Ingress and then 404s every asset and every API call.
# That is not a guess: an add-on built on 5.0.4 answered the header with an
# unchanged base href, because the fix is not in it.
FROM ghcr.io/hms-homelab/hms-cpap:5.1.0

# jq to read /data/options.json. curl is already present, since the image's own
# HEALTHCHECK uses it, and the entrypoint uses it to ask the Supervisor for the
# MQTT broker's credentials.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

COPY run.sh /run.sh
RUN chmod +x /run.sh

# Stays root, where the base image drops to the `cpap` user.
#
# The Supervisor mounts its own directories over /data and /config, owned by
# root, and an add-on cannot chown them from inside because it is not root by
# then. Running as `cpap` therefore dies on the first write:
#
#   /run.sh: cannot create /config/config.json: Permission denied
#
# Root is the norm for an add-on, the container is isolated by the Supervisor,
# and it is what makes the mapped folders usable. The standalone Docker image is
# untouched and still drops privileges.
ENTRYPOINT []
CMD ["/run.sh"]
