FROM alpine:3.16 AS geos
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/libgeos/geos/archive/3.11.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake \
 && cd /tmp/geos-* \
 && mkdir build \
 && cd build \
 && cmake -DCMAKE_BUILD_TYPE=Release .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

FROM alpine:3.16 AS proj_gdal
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/PROJ/archive/9.1.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake sqlite sqlite-dev tiff-dev curl-dev \
 && cd /tmp/PROJ-* \
 && mkdir build \
 && cd build \
 && cmake .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/gdal/archive/v3.5.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base cmake linux-headers sqlite-dev tiff-dev curl-dev \
 && cd /tmp/gdal-* \
 && mkdir build \
 && cd build \
 && cmake .. \
 && cmake --build . \
 && cmake --build . --target install \
 && apk del .build-deps \
 && rm -r /tmp/*

FROM alpine:3.16 AS postgres_base
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_15_BETA4.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base \
  linux-headers \
  bison \
  flex \
  python3-dev \
  libxml2-dev \
  libxslt-dev \
  icu-dev \
  openssl-dev \
  autoconf \
  automake \
  libtool \
  clang-dev \
  llvm13-dev \
  \
 && cd /tmp/postgres-* \
 && ./configure \
  --prefix=/usr/local \
  --without-readline \
  --with-libxml \
  --with-libxslt \
  --with-python \
  --with-icu \
  --with-openssl \
 && make \
 && make install \
 && cd contrib \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# postgis
COPY --from=geos /usr/local /usr/local
COPY --from=proj_gdal /usr/local /usr/local
RUN set -x \
 && cd /tmp \
 # && wget -qO- https://github.com/postgis/postgis/archive/3.3.0.tar.gz | tar xz \
 && wget -qO- https://postgis.net/stuff/postgis-3.3.1dev.tar.gz | tar xz \
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
  llvm13-dev \
  \
 && cd /tmp/postgis-* \
 && ./autogen.sh \
 && ./configure \
  # topology breaks `make install`, don't know how to fix
  --without-topology \
 && make \
 && make install \
 && make comments-install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/v1.4.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base clang llvm13-dev \
 && cd /tmp/pg_cron-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && apk add --no-cache \
  libxml2 \
  libxslt \
  python3 \
  protobuf-c \
  json-c \
  icu \
  openssl \
  libcurl \
  tiff \
  llvm13 \
 && adduser --uid 70 \
  --disabled-password \
  --home /var/lib/postgresql \
  postgres

RUN set -x \
 && rm /usr/local/lib/*.a \
 && rm -r /usr/local/include

FROM scratch
MAINTAINER Vladislav Nezhutin <exe-dealer@yandex.ru>
COPY --from=postgres_base / /
# FIXME hub.docker.com does not preserve ownership
# RUN chown -R postgres:postgres /var/lib/postgresql
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
  "# config is extracted out of docker volume to make" \
  "# possible to deploy new config with new docker image" \
  "include '/var/lib/postgresql/postgresql.conf'" \
  "# but you can override settings below if need" \
  > $PGDATA/postgresql.conf \
  \
 && printf %s\\n \
  "listen_addresses='0.0.0.0'" \
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

# ONBUILD COPY . ./
# ONBUILD RUN set -x \
#  && initdb \
#  && rm $PGDATA/postgresql.conf $PGDATA/pg_hba.conf \
#  && pg_ctl --silent --wait start -o "-c config_file=conf/postgresql.on_migration.conf" \
#  && (cd init && psql -v ON_ERROR_STOP=1 -f init.sql) \
#  && find migrations -type f -mindepth 2 -maxdepth 2 -name '*.sql' \
#   # find latest migration for each db
#   | sort -r | awk -F/ '{ print $3, $2 }' | uniq -f1 | awk '{ print $2, $1 }' \
#   | xargs -rn2 printf "ALTER DATABASE \"%s\" SET migration.latest = '%s';\n" \
#   | psql -v ON_ERROR_STOP=1 \
#  && pg_ctl --silent --wait stop
# ONBUILD VOLUME $PGDATA
