FROM ubuntu:20.04 as base
WORKDIR /workdir

ARG arch=amd64
ARG crossarch=arm-zephyr-eabi
ARG ZEPHYR_TOOLCHAIN_VERSION=0.16.0
ARG ZEPHYR_TOOLCHAIN_ARCHIVE_FORMAT=xz
ARG WEST_VERSION=1.0.0
# These are the legacy utils, see https://github.com/NordicPlayground/nrf-docker/issues/68
ARG NRF_UTIL_VERSION=6.1.7
ARG NORDIC_COMMAND_LINE_TOOLS_VERSION="10-21-0/nrf-command-line-tools-10.21.0"

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN mkdir /workdir/.cache && \
    apt-get -y update && \
    apt-get -y upgrade && \
    apt-get -y install \
        wget \
        python3-pip \
        python3-venv \
        ninja-build \
        gperf \
        git \
        unzip \
        libncurses5 libncurses5-dev \
        libyaml-dev libfdt1 \
        libusb-1.0-0-dev udev \
        device-tree-compiler \
        xz-utils \
        file \
        ruby && \
    case $arch in \
    "amd64") \
        apt-get -y install gcc-multilib \
        ;; \
    esac && \
    apt-get -y clean && apt-get -y autoremove && \
    #
    # Latest PIP & Python dependencies
    #
    python3 -m pip install -U pip && \
    python3 -m pip install -U pipx && \
    python3 -m pip install -U setuptools && \
    python3 -m pip install 'cmake>=3.20.0' wheel && \
    python3 -m pip install -U "west==${WEST_VERSION}" && \
    python3 -m pip install pc_ble_driver_py && \
    # Newer PIP will not overwrite distutils, so upgrade PyYAML manually
    python3 -m pip install --ignore-installed -U PyYAML && \
    #
    # Isolated command line tools
    # No nrfutil 6+ release for arm64 (M1/M2 Macs) and Python 3, yet: https://github.com/NordicSemiconductor/pc-ble-driver-py/issues/227
    #
    case $arch in \
    "amd64") \
        PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
        pipx install "nrfutil==${NRF_UTIL_VERSION}" \
        ;; \
    esac && \
    #
    # ClangFormat
    #
    python3 -m pip install -U six && \
    apt-get -y install clang-format && \
    wget -qO- https://raw.githubusercontent.com/nrfconnect/sdk-nrf/main/.clang-format > /workdir/.clang-format && \
    #
    # Nordic command line tools
    # Releases: https://www.nordicsemi.com/Products/Development-tools/nrf-command-line-tools/download
    NCLT_BASE=https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/desktop-software/nrf-command-line-tools/sw/versions-10-x-x && \
    echo "Host architecture: $arch" && \
    case $arch in \
        "amd64") \
            NCLT_URL="${NCLT_BASE}/${NORDIC_COMMAND_LINE_TOOLS_VERSION}_linux-amd64.tar.gz" \
            ;; \
        "arm64") \
            NCLT_URL="${NCLT_BASE}/${NORDIC_COMMAND_LINE_TOOLS_VERSION}_linux-arm64.tar.gz" \
            ;; \
    esac && \
    echo "NCLT_URL=${NCLT_URL}" && \
    if [ ! -z "$NCLT_URL" ]; then \
        mkdir tmp && cd tmp && \
        wget -qO - "${NCLT_URL}" | tar --no-same-owner -xz && \
        # Install included JLink
        mkdir /opt/SEGGER && \
        tar xzf JLink_*.tgz -C /opt/SEGGER && \
        mv /opt/SEGGER/JLink* /opt/SEGGER/JLink && \
        # Install nrf-command-line-tools
        cp -r ./nrf-command-line-tools /opt && \
        ln -s /opt/nrf-command-line-tools/bin/nrfjprog /usr/local/bin/nrfjprog && \
        ln -s /opt/nrf-command-line-tools/bin/mergehex /usr/local/bin/mergehex && \
        cd .. && rm -rf tmp ; \
    else \
        echo "Skipping nRF Command Line Tools (not available for $arch)" ; \
    fi && \
    #
    # Zephyr Toolchain
    # Releases: https://github.com/zephyrproject-rtos/sdk-ng/releases
    #
    echo "Host architecture: ${arch}" && \
    echo "Target architecture: ${crossarch}" && \
    echo "Zephyr Toolchain version: ${ZEPHYR_TOOLCHAIN_VERSION}" && \
    case $arch in \
        "amd64") \
            ZEPHYR_MINIMAL_BUNDLE_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_TOOLCHAIN_VERSION}/zephyr-sdk-${ZEPHYR_TOOLCHAIN_VERSION}_linux-x86_64_minimal.tar.${ZEPHYR_TOOLCHAIN_ARCHIVE_FORMAT}" \
            ;; \
        "arm64") \
            ZEPHYR_MINIMAL_BUNDLE_URL="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${ZEPHYR_TOOLCHAIN_VERSION}/zephyr-sdk-${ZEPHYR_TOOLCHAIN_VERSION}_macos-aarch64_minimal.tar.${ZEPHYR_TOOLCHAIN_ARCHIVE_FORMAT}" \
            ;; \
        *) \
            echo "Unsupported host architecture: \"${arch}\"" >&2 && \
            exit 1 ;; \
    esac && \
    echo "Install Zephyr SDK from ZEPHYR_MINIMAL_BUNDLE_URL=${ZEPHYR_MINIMAL_BUNDLE_URL}" && \
    case $ZEPHYR_TOOLCHAIN_ARCHIVE_FORMAT in \
        "gz") \
            wget -qO - "${ZEPHYR_MINIMAL_BUNDLE_URL}" | tar xz;; \
        *) \
            wget -qO - "${ZEPHYR_MINIMAL_BUNDLE_URL}" | tar xJ;; \
    esac && \
    mv /workdir/zephyr-sdk-${ZEPHYR_TOOLCHAIN_VERSION} /workdir/zephyr-sdk && cd /workdir/zephyr-sdk && \
    case $arch in \
        "arm64") \
            ./setup.sh -t aarch64-zephyr-elf -c \
            ;; \
        *) \
            yes | ./setup.sh -t ${crossarch} \
            ;; \
    esac && \
    #
    # Install Python 3.8 for older toolchain versions
    #
    if [ $(expr match "$ZEPHYR_TOOLCHAIN_VERSION" "0\.14\.*") -ne 0 ]; then \
        apt-get -y install software-properties-common && \
        add-apt-repository -y ppa:deadsnakes/ppa && \
        apt-get -y update && \
        apt-get -y install python3.8 python3.8-dev && \
        python3.8 --version; \
    fi

# Download sdk-nrf and west dependencies to install pip requirements
FROM base
ARG sdk_nrf_revision=main
ARG sdk_nrf_commit
RUN \
    west init -m https://github.com/nrfconnect/sdk-nrf --mr ${sdk_nrf_revision} && \
    if [[ $sdk_nrf_commit =~ "^[a-fA-F0-9]{32}$" ]]; then \
        git checkout ${sdk_nrf_revision} ; \
    fi && \
    west update --narrow -o=--depth=1 && \
    echo "Installing requirements: zephyr/scripts/requirements.txt" && \
    python3 -m pip install -r zephyr/scripts/requirements.txt && \
    # Install only the requirements needed for building firmware, not documentation
    echo "Installing requirements: nrf/scripts/requirements-base.txt" && \
    python3 -m pip install -r nrf/scripts/requirements-base.txt && \
    echo "Installing requirements: nrf/scripts/requirements-build.txt" && \
    python3 -m pip install -r nrf/scripts/requirements-build.txt && \
    echo "Installing requirements: bootloader/mcuboot/scripts/requirements.txt" && \
    python3 -m pip install -r bootloader/mcuboot/scripts/requirements.txt

RUN mkdir /workdir/project

WORKDIR /workdir/project
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV XDG_CACHE_HOME=/workdir/.cache
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr
ENV ZEPHYR_SDK_INSTALL_DIR=/workdir/zephyr-sdk
ENV ZEPHYR_BASE=/workdir/zephyr
ENV PATH="${ZEPHYR_BASE}/scripts:${PATH}"
