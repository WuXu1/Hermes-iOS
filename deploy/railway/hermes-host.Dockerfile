# Hermes Agent + Hermes Mobile connector, for Railway (or any container host).
#
# Build context is the repo root:
#   docker build -f deploy/railway/hermes-host.Dockerfile .
#
# Mount a persistent volume at /opt/data (HERMES_HOME + connector state).
# The -desktop variant adds Bot Screen: an Xfce desktop + Chromium you can take
# over from Hermes Desktop to sign in to sites the agent then stays signed in to.
FROM nousresearch/hermes-agent:v2026.9.24-desktop

USER root

COPY connector /opt/hermes-mobile/connector
COPY skills/hermes-ios /opt/hermes-mobile/skills/hermes-ios
COPY deploy/railway/roles /opt/hermes-mobile/roles
COPY --chmod=0755 deploy/railway/hermes-host-start.sh /opt/hermes-mobile/start.sh

# Document reading: Hermes installs its converter on first use, but the agent
# can't write to its venv at runtime, so bake it in. Poppler renders scanned
# PDF pages to images for the main model to read.
RUN apt-get update && apt-get install -y --no-install-recommends poppler-utils && \
    rm -rf /var/lib/apt/lists/* && \
    uv pip install --python /opt/hermes/.venv/bin/python --no-cache firecrawl-anydoc==0.2.4

# hermes-webui: a browser UI for this Hermes, and the server the Hermex iOS app
# connects to. It runs Hermes in-process on Hermes's own venv, so it lives here.
ARG HERMES_WEBUI_REF=c296673ebfaf98750fe38438bc71f0cbb1f75777
RUN mkdir -p /opt/hermes-webui && \
    curl -fsSL "https://github.com/nesquena/hermes-webui/archive/${HERMES_WEBUI_REF}.tar.gz" \
        | tar xz -C /opt/hermes-webui --strip-components=1 && \
    chown -R hermes /opt/hermes-webui

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
