# Arguments shared between the build image and the final one.
ARG APP_USER="app"
ARG APP_PATH="/home/${APP_USER}"
ARG VENV_NAME=".venv"
# Always pin dependencies strictly.
# Equivalent to: python:3.12.4-alpine3.20
ARG PYTHON_IMAGE="python@sha256:ff870bf7c2bb546419aaea570f0a1c28c8103b78743a2b8030e9e97391ddf81b"

# BUILD IMAGE
FROM ${PYTHON_IMAGE} AS build

# Arguments
ARG APP_PATH
ARG VENV_NAME
ARG VENV_PATH="${APP_PATH}/${VENV_NAME}"

# Install as root.
USER root

# Make sure our tools are resolved, once installed.
ENV PATH="/root/.local/bin:${PATH}"

RUN set -xeEuo pipefail \
 # Install build tools.
 && pip install --user pipx \
 && pipx install pdm uv \
 # Create the app directory.
 && mkdir "${APP_PATH}" \
 #  Create the virtual environment for the project.
 && uv venv "${VENV_PATH}" \
    ;

# Switch to the app directory.
WORKDIR "${APP_PATH}"

# Copy all our resources.
COPY . .

RUN set -xeEuo pipefail \
 # Check the dependencies were locked.
 && pdm lock --check --prod \
 # Package our project as a wheel.
 && pdm build --no-sdist \
 # Export the dependencies.
 && pdm export --prod -f requirements -o requirements.txt \
 # Install the dependencies.
 && uv pip install -r requirements.txt \
 # Install the project. \
 && uv pip install dist/*.whl \
 # Keep only the binaries we need. \
# && mv "${VENV_PATH}"/bin/python "${VENV_PATH}"/bin/uvicorn . \
# && rm -rf ${VENV_PATH}/bin/* \
# && mv uvicorn python "${VENV_PATH}/bin" \
  # TODO revenir sur ça
  && find "${VENV_PATH}/bin" -type f ! -name python ! -name uvicorn -exec rm -f {} + \
 #  Delete __pycache__
 && find "${APP_PATH}" -name __pycache__ -type d -exec rm -rf {} + \
    ;
# tODO faire des checks à la fin, genre pas de pip, pas de pycache.


# FINAL IMAGE
FROM ${PYTHON_IMAGE}

# Arguments
ARG APP_USER
ARG APP_PATH
ARG VENV_NAME
ARG VENV_PATH="${APP_PATH}/${VENV_NAME}"

# Install as root.
USER root

RUN set -xeEuo pipefail \
 #  Install tini.
 && apk add --no-cache tini \
 #  Create the applicative user.
 && adduser -D -u 5000 -h "${APP_PATH}" "${APP_USER}" \
    ;

# Copy the virtual environment and the main.
COPY --from=build --chown="${APP_USER}:${APP_USER}" "${VENV_PATH}" "${VENV_PATH}"
COPY --chown="${APP_USER}:${APP_USER}" main.py "${APP_PATH}"

# Run as the applicative user.
USER "${APP_USER}"
WORKDIR  "${APP_PATH}"

# Make sure the virtual environment is resolved.
ENV PATH="${VENV_PATH}/bin:${PATH}"

# Set a healthcheck for the container.
# TODO can we run the healthcheck as fast as possible so that we don't penalize the startup time ?
# Or do we get rid of it and rely on the k8s probes ?
# HEALTHCHECK --interval=5s --timeout=5s --retries=3 CMD bash -c 'echo > /dev/tcp/0.0.0.0/8080'

# Make sure that tini is the process of PID 1.
ENTRYPOINT ["tini", "--", "python", "-m", "main"]
