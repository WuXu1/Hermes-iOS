# Hermes Agent + Hermes Mobile connector, for Railway (or any container host).
#
# Build context is the repo root:
#   docker build -f deploy/railway/hermes-host.Dockerfile .
#
# Mount a persistent volume at /opt/data (HERMES_HOME + connector state).
FROM nousresearch/hermes-agent:v2026.9.24

USER root

COPY connector /opt/hermes-mobile/connector
COPY skills/hermes-ios /opt/hermes-mobile/skills/hermes-ios
COPY deploy/railway/roles /opt/hermes-mobile/roles
COPY --chmod=0755 deploy/railway/hermes-host-start.sh /opt/hermes-mobile/start.sh

RUN python3 -m venv /opt/hermes-mobile/.venv && \
    /opt/hermes-mobile/.venv/bin/python -m pip install --no-cache-dir /opt/hermes-mobile/connector && \
    /opt/hermes-mobile/.venv/bin/hermes-mobile --help >/dev/null

ENV PATH="/opt/hermes-mobile/.venv/bin:${PATH}" \
    HERMES_MOBILE_CONNECTOR_HOME=/opt/data/.hermes-mobile \
    HERMES_COMMAND=/opt/hermes/bin/hermes \
    HERMES_WORKDIR=/opt/data/workspace \
    HERMES_PROVIDER=deepseek \
    HERMES_MODEL=deepseek-flash \
    HERMES_GATEWAY_BOOTSTRAP_STATE=running

# The upstream entrypoint (s6 /init + main-wrapper) drops to the `hermes`
# user with HOME=/opt/data before running this command.
CMD ["/opt/hermes-mobile/start.sh"]
