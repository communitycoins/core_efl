###########################################################
# Stage 1: Berkeley DB 4.8 (prebuilt, frozen)
###########################################################
FROM communitycoins/berkeley-db-4.8:24.04 AS stage-1-bdb


###########################################################
# Stage 2: Builder - eguldend + egulden-cli
###########################################################
FROM ubuntu:24.04 AS stage-2-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libtool \
    autotools-dev \
    automake \
    pkg-config \
    python3 \
    git \
    bsdmainutils \
    libssl-dev \
    libevent-dev \
    libboost-system-dev \
    libboost-filesystem-dev \
    libboost-chrono-dev \
    libboost-program-options-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libzmq3-dev \
    libminiupnpc-dev \
    util-linux \
 && rm -rf /var/lib/apt/lists/*

# hexdump compatibility (Ubuntu → util-linux)
RUN [ -e /usr/bin/hexdump ] || ln -s "$(which hexdump)" /usr/bin/hexdump

# Bring in Berkeley DB 4.8
COPY --from=stage-1-bdb /usr/local/bdb48 /usr/local/bdb48

ENV BDB_CFLAGS="-I/usr/local/bdb48/include"
ENV BDB_LIBS="-L/usr/local/bdb48/lib -ldb_cxx-4.8"
ENV LD_LIBRARY_PATH="/usr/local/bdb48/lib"

# ---- eGulden source ----
WORKDIR /src
COPY . .

# Build egulden
RUN ./autogen.sh && \
    ./configure \
      --with-boost-libdir=/usr/lib/x86_64-linux-gnu \
      --without-gui \
      --with-incompatible-bdb \
      --disable-bench \
      CPPFLAGS="${BDB_CFLAGS}" \
      LDFLAGS="${BDB_LIBS}" && \
    make -j$(nproc)

# Install binaries to known location
RUN install -m 0755 src/eguldend     /usr/local/bin/eguldend && \
    install -m 0755 src/egulden-cli  /usr/local/bin/egulden-cli && \
    strip /usr/local/bin/eguldend /usr/local/bin/egulden-cli


###########################################################
# Stage 3: Runtime - minimal wallet-daemon image
###########################################################
FROM ubuntu:24.04 AS stage-3-runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libboost-filesystem1.83.0 \
    libboost-program-options1.83.0 \
    libboost-thread1.83.0 \
    libboost-chrono1.83.0 \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libzmq5 \
    libminiupnpc17 \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Berkeley DB runtime
COPY --from=stage-1-bdb /usr/local/bdb48 /usr/local/bdb48
ENV LD_LIBRARY_PATH="/usr/local/bdb48/lib"

# Non-root user
ARG COIN_NAME=egulden
ENV COIN=${COIN_NAME}
ENV HOME=/${COIN}

RUN groupadd -g 1001 ${COIN} \
 && useradd -u 1001 -g ${COIN} -s /bin/bash -m -d ${HOME} ${COIN} \
 && mkdir -p ${HOME}/data \
 && chown -R ${COIN}:${COIN} ${HOME}

# Binaries
COPY --from=stage-2-builder /usr/local/bin/eguldend     /usr/local/bin/eguldend
COPY --from=stage-2-builder /usr/local/bin/egulden-cli /usr/local/bin/egulden-cli

USER ${COIN}
WORKDIR ${HOME}

VOLUME ["${HOME}/data"]

# eGulden ports
EXPOSE 11015 21015

# Let docker-compose control execution
ENTRYPOINT []
CMD ["eguldend"]
