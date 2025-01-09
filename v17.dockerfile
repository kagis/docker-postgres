FROM alpine:3.21.2

RUN set -x \
 && apk add --no-cache \
  readline icu-libs llvm19-libs tzdata \
  python3 libxml2 libxslt lz4-libs openssl \
  protobuf-c json-c sqlite tiff curl jq \
 && adduser --uid 70 \
  --system \
  --disabled-password \
  --home /var/lib/postgresql \
  postgres

RUN set -x \
 && cd /tmp \
 # https://github.com/postgres/postgres/tags
 && wget -qO- https://github.com/postgres/postgres/archive/REL_17_2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base automake libtool autoconf bison flex clang19 \
  readline-dev icu-dev llvm19-dev linux-headers \
  python3-dev libxml2-dev libxslt-dev lz4-dev openssl-dev \
 && cd /tmp/postgres-* \
 && ./configure \
  --prefix=/usr/local \
  --with-python \
  --with-libxml \
  --with-libxslt \
  --with-lz4 \
  --with-ssl=openssl \
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
 # https://github.com/libgeos/geos/releases
 && wget -qO- https://github.com/libgeos/geos/archive/3.13.0.tar.gz | tar xz \
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
 # https://github.com/OSGeo/PROJ/releases
 && wget -qO- https://github.com/OSGeo/PROJ/archive/9.5.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake sqlite-dev tiff-dev curl-dev \
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
 # https://github.com/OSGeo/gdal/releases
 && wget -qO- https://github.com/OSGeo/gdal/archive/v3.10.0.tar.gz | tar xz \
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
 # https://github.com/postgis/postgis/tags
 && wget -qO- https://github.com/postgis/postgis/archive/3.5.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base autoconf automake libtool \
  libxslt-dev json-c-dev protobuf-c-dev \
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
 # https://github.com/citusdata/pg_cron/releases
 && wget -qO- https://github.com/citusdata/pg_cron/archive/v1.6.4.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base \
 && cd /tmp/pg_cron-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && rm /usr/local/lib/*.a \
 # && rm -r /usr/local/include \
 ;

FROM scratch
MAINTAINER Vladislav Nezhutin <exe-dealer@yandex.kz>
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
  "#     db   user addr method" \
  "host  all  all  all  trust" \
  "local all  all       trust" \
  > pg_hba.conf

VOLUME $PGDATA
