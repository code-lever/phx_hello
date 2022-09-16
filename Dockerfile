# File: hello/Dockerfile

# Use the HexPM docker image for building the release
# https://github.com/hexpm/bob#docker-images
# This Dockerfile is based on the following images:
#  - https://hub.docker.com/layers/hexpm/elixir/1.14.0-erlang-25.0.4-ubuntu-jammy-20220428/images/sha256-a38946d362ba922840f875d291ec95652ce21b47a5d069c47c47cdd4f12b17f9?context=explore
#  - https://hub.docker.com/layers/library/ubuntu/jammy-20220428/images/sha256-aa6c2c047467afc828e77e306041b7fa4a65734fe3449a54aa9c280822b0d87d?context=explore
ARG ELIXIR_VERSION=1.14.0
ARG OTP_VERSION=25.0.4
# Ubuntu 22.04.1 LTS (Jammy Jellyfish)
ARG UBUNTU_VERSION=jammy-20220428

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION}"
# Run the release with the same version of vanilla Ubuntu
ARG RUNNER_IMAGE="ubuntu:${UBUNTU_VERSION}"

ARG APP_NAME=hello
# The directory where the application will be built in the builder image
# In the runner image, it will be run in a system users home directory
# in a subdirectory with the same name
ARG APP_ROOT="/app"

FROM ${BUILDER_IMAGE} as builder
ARG APP_NAME
ARG APP_ROOT

# install build dependencies
RUN apt-get update -y \
    && apt-get install -y build-essential git \
    && apt-get install -y curl \
    && apt-get clean \
    && rm -f /var/lib/apt/lists/*_*

# Install Node.js LTS (v16.x)
# https://github.com/nodesource/distributions/blob/master/README.md
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - &&\
    apt-get install -y nodejs

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# prepare build dir
WORKDIR ${APP_ROOT}

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib

# compile assets
RUN cd assets \
    && npm ci
RUN mix assets.deploy
# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

########################################################################

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} as runner
ARG APP_NAME
ARG APP_ROOT
ENV MIX_ENV="prod"

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

#WORKDIR ${APP_ROOT}
ENV USER="elixir"

# Creates an system user to be used exclusively to run the app
# This user has the shell /usr/sbin/nologin
RUN adduser --system --group --uid=1000 ${USER}
# Make a directory to hold the release, in the system users home directory
RUN mkdir "/home/${USER}${APP_ROOT}"
# Give the user ownership of its home directory
RUN chown -R "${USER}:${USER}" "/home/${USER}"

# Everything from this line onwards will run in the context of the system user.
USER "${USER}"

# Copy the release to the system users home directory
WORKDIR "/home/${USER}${APP_ROOT}"
COPY --from=builder --chown="${USER}":"${USER}" ${APP_ROOT}/_build/${MIX_ENV}/rel/${APP_NAME} ./

CMD ./bin/server