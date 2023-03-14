FROM ubuntu:20.04

# This the release tag of virtual-environments: https://github.com/actions/virtual-environments/releases
ARG UBUNTU_VERSION=2004
ARG VIRTUAL_ENVIRONMENT_VERSION=ubuntu20/20230109.1

ENV UBUNTU_VERSION=${UBUNTU_VERSION} VIRTUAL_ENVIRONMENT_VERSION=${VIRTUAL_ENVIRONMENT_VERSION}

# Set environment variable to prevent interactive installation
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install base packages.
RUN apt update && TZ=Etc/UTC \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo=1.8.* \
    lsb-release=11.1.* \
    software-properties-common=0.99.* \
    gnupg-agent=2.2.* \
    openssh-client=1:8.* \
    make=4.*\
    rsync \
    wget \
    jq=1.* \
    gcc \
    g++ \
    clang \
    llvm \
    curl && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add sudo rule for runner user
RUN echo "runner ALL= EXEC: NOPASSWD:ALL" >> /etc/sudoers.d/runner

# Update git.
RUN add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get -y install --no-install-recommends git && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install docker cli.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg > /etc/apt/trusted.gpg.d/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli=5:20.10.* && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install rust using rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y

# Add Kitware APT repository for updated CMake version
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates gnupg && \
    apt-key adv --fetch-keys 'https://apt.kitware.com/keys/kitware-archive-latest.asc' && \
    echo 'deb https://apt.kitware.com/ubuntu/ focal main' > /etc/apt/sources.list.d/kitware.list && \
    apt-get update


# Install build-essential and update cmake
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    apt-get update && \
    apt-get install -y --no-install-recommends gcc-10 g++-10 && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 --slave /usr/bin/g++ g++ /usr/bin/g++-10 && \
    apt-get install -y --no-install-recommends build-essential cmake && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*


# Install the required dependencies to build TensorFlow from source
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.9-dev \
    python3.9-venv \
    python3.9-distutils \
    python3-pip \
    python3-numpy \
    python3-wheel && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install the Bazel version 5.3.0
ARG BAZEL_VERSION=5.3.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    && curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > bazel.gpg && \
    mv bazel.gpg /etc/apt/trusted.gpg.d/ && \
    echo "deb [arch=$(dpkg --print-architecture)] https://storage.googleapis.com/bazel-apt stable jdk1.8" > /etc/apt/sources.list.d/bazel.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends bazel-${BAZEL_VERSION} && \
    ln -s /usr/bin/bazel-${BAZEL_VERSION} /usr/bin/bazel && \
    ldconfig && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*



# Clone the TensorFlow
ARG TF_VERSION=v2.11.0

RUN git clone https://github.com/tensorflow/tensorflow.git /tensorflow \
    && cd /tensorflow \
    && git checkout ${TF_VERSION} \
    && git submodule update --init --recursive

# Configure TensorFlow build
RUN cd /tensorflow \
    && ./configure


# Build TensorFlow with bazel example
# RUN cd /tensorflow \
#    && bazel build --config=opt //tensorflow/tools/pip_package:build_pip_package \
#    && bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg


# Build TensorFlow with bazel
# https://github.com/nubispc/container-build-example/blob/86d84a184f90781c3eb2d47c87502fe14ba50361/Dockerfile.tensorflow-plugin#L106
RUN cd /tensorflow \
    && bazel build --local_ram_resources=HOST_RAM*.7 \
            --local_cpu_resources=HOST_CPUS-1 \
            --jobs=4 \
            --config=v2 \
            --copt=-O3 \
            --copt=-m64 \
            --copt=-march=native \
            --config=opt \
            --verbose_failures \
            //tensorflow:tensorflow_cc \
            //tensorflow:install_headers \
            //tensorflow:tensorflow \
            //tensorflow:tensorflow_framework \
            //tensorflow/c:c_api \
            //tensorflow/tools/lib_package:libtensorflow

# Copy scripts.
COPY scripts/ /usr/local/bin/

# Install additional distro packages and runner virtual envs
ARG VIRTUAL_ENV_PACKAGES=""
ARG VIRTUAL_ENV_INSTALLS="basic python nodejs"
RUN apt-get -y update && \
    ( [ -z "$VIRTUAL_ENV_PACKAGES" ] || apt-get -y --no-install-recommends install $VIRTUAL_ENV_PACKAGES ) && \
    . /usr/local/bin/install-from-virtual-env-helpers && \
    for package in ${VIRTUAL_ENV_INSTALLS}; do \
        install-from-virtual-env $package;  \
    done && \
    apt-get -y install --no-install-recommends gosu=1.* && \
    apt-get -y clean && \
    rm -rf /virtual-environments /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install runner and its dependencies.
RUN groupadd -g 121 runner && useradd -mr -d /home/runner -u 1001 -g 121 runner && \
    install-runner

COPY entrypoint.sh /
WORKDIR /home/runner
USER runner
ENTRYPOINT ["/entrypoint.sh"]
