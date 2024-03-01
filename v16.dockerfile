FROM alpine:3.19.1

RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_16_2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base \
  linux-headers \
  bison \
  flex \
  readline-dev \
  python3-dev \
  libxml2-dev \
  libxslt-dev \
  icu-dev \
  openssl-dev \
  lz4-dev \
  autoconf \
  automake \
  libtool \
  clang-dev \
  llvm17-dev \
  \
 && cd /tmp/postgres-* \
 && ./configure \
  --prefix=/usr/local \
  --with-libxml \
  --with-libxslt \
  --with-python \
  --with-ssl=openssl \
  --with-lz4 \
  --with-system-tzdata=/usr/share/zoneinfo \
 && make \
 && make install \
 && cd contrib \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# geos (postgis)
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/libgeos/geos/archive/3.12.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake \
 && cd /tmp/geos-* \
 && mkdir build \
 && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

# proj (postgis)
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/PROJ/archive/9.3.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake sqlite sqlite-dev tiff-dev curl-dev \
 && cd /tmp/PROJ-* \
 && mkdir build \
 && cd build \
 && cmake .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

# gdal (postgis)
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/gdal/archive/v3.8.4.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake linux-headers sqlite-dev tiff-dev curl-dev \
 && cd /tmp/gdal-* \
 && mkdir build \
 && cd build \
 && cmake .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

# postgis
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgis/postgis/archive/3.4.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base \
  autoconf \
  automake \
  libtool \
  # postgis не устанаваливается через CREATE EXTENSION без libxslt-dev
  libxslt-dev \
  libxml2-dev \
  json-c-dev \
  protobuf-c-dev \
  sqlite-dev \
  tiff-dev \
  curl-dev \
  clang-dev \
  llvm17-dev \
  \
 && cd /tmp/postgis-* \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && make comments-install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/refs/tags/v1.6.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base clang llvm17-dev \
 && cd /tmp/pg_cron-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && apk add --no-cache \
  readline \
  libxml2 \
  libxslt \
  python3 \
  protobuf-c \
  json-c \
  icu \
  openssl \
  lz4-libs \
  libcurl \
  tiff \
  llvm17-libs \
  tzdata \
  jq \
 && adduser --uid 70 \
  --disabled-password \
  --home /var/lib/postgresql \
  postgres

RUN set -x \
 && rm /usr/local/lib/*.a \
 # && rm -r /usr/local/include \
 ;

FROM scratch
MAINTAINER Vladislav Nezhutin <exe-dealer@yandex.ru>
COPY --from=0 / /
USER postgres
WORKDIR /var/lib/postgresql
ENV PGDATA=/var/lib/postgresql/data
EXPOSE 5432
CMD ["postgres"]

RUN mkdir $PGDATA \
 && initdb \
 && mv $PGDATA/postgresql.conf $PGDATA/postgresql.conf.sample \
 && mv $PGDATA/pg_hba.conf $PGDATA/pg_hba.conf.sample \
 # this log duplicates stderr, not need it
 && ln -s /dev/null log \
 # redirect json logs to stdout
 && ln -s /dev/stdout log.json  \
  \
 && printf %s\\n \
  "# config is located outside the docker volume to make" \
  "# possible to deploy new config with new docker image" \
  "include '/var/lib/postgresql/postgresql.conf'" \
  "# but you can override settings below if need" \
  > $PGDATA/postgresql.conf \
  \
 && printf %s\\n \
  "listen_addresses='0.0.0.0'" \
  "default_toast_compression=lz4" \
  "shared_buffers=128MB" \
  "work_mem=32MB" \
  "wal_level=logical" \
  "log_timezone=UTC" \
  "timezone=UTC" \
  "tcp_keepalives_count=5" \
  "tcp_keepalives_idle=60" \
  "tcp_keepalives_interval=10" \
  "hba_file='pg_hba.conf'" \
  "log_destination=jsonlog" \
  "logging_collector=on" \
  "log_directory='$PWD'" \
  "log_filename=log" \
  "log_rotation_age=0" \
  "log_rotation_size=0" \
  "shared_preload_libraries='pg_cron'" \
  "cron.database_name=postgres" \
  "cron.log_statement=off" \
  > postgresql.conf \
  \
 && printf %s\\n \
  "#    db     user addr method" \
  "host all    all  all  trust" \
  > pg_hba.conf

VOLUME $PGDATA
