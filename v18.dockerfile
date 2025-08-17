# https://alpinelinux.org/releases/
FROM alpine:3.22.1

WORKDIR /tmp

RUN set -x \
 && apk add --no-cache \
  readline icu-libs llvm20-libs tzdata \
  python3 libxml2 libxslt lz4-libs openssl \
  protobuf-c json-c sqlite tiff curl jq

# proj https://github.com/OSGeo/PROJ/tags
RUN set -x \
  && wget -qO- https://github.com/OSGeo/PROJ/archive/9.6.2.tar.gz | tar -xz --strip-components=1 \
  && apk add --no-cache --virtual .build-deps build-base cmake sqlite-dev tiff-dev curl-dev \
  && mkdir build \
  && cd build \
  && cmake .. \
  && cmake --build . \
  && cmake --build . --target install \
  && apk del .build-deps \
  && rm -r /tmp/*

# geos https://github.com/libgeos/geos/tags
RUN set -x \
  && wget -qO- https://github.com/libgeos/geos/archive/3.13.1.tar.gz | tar -xz --strip-components=1 \
  && apk add --no-cache --virtual .build-deps build-base cmake \
  && mkdir build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release .. \
  && cmake --build . \
  && cmake --build . --target install \
  && apk del .build-deps \
  && rm -r /tmp/*

# gdal https://github.com/OSGeo/gdal/tags
RUN set -x \
  && wget -qO- https://github.com/OSGeo/gdal/archive/v3.11.3.tar.gz | tar -xz --strip-components=1 \
  && apk add --no-cache --virtual .build-deps build-base cmake linux-headers sqlite-dev tiff-dev curl-dev \
  && mkdir build \
  && cd build \
  && cmake .. \
  && cmake --build . \
  && cmake --build . --target install \
  && apk del .build-deps \
  && rm -r /tmp/*

# postgres https://github.com/postgres/postgres/tags
RUN set -x \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_18_BETA3.tar.gz | tar -xz --strip-components=1 \
 && apk add --no-cache --virtual .build-deps \
  build-base automake libtool autoconf bison flex clang20 \
  readline-dev icu-dev llvm20-dev linux-headers \
  python3-dev libxml2-dev libxslt-dev lz4-dev openssl-dev \
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

# postgis https://github.com/postgis/postgis/tags
RUN set -x \
 && wget -qO- https://github.com/postgis/postgis/archive/3.6.0beta1.tar.gz | tar -xz --strip-components=1 \
 && apk add --no-cache --virtual .build-deps \
  build-base autoconf automake libtool \
  libxslt-dev json-c-dev protobuf-c-dev \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && make comments-install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron https://github.com/citusdata/pg_cron/tags
RUN set -x \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/0c7f00b3bec7946a5d54edd62d181e1baf937402.tar.gz | tar -xz --strip-components=1 \
 && apk add --no-cache --virtual .build-deps build-base \
 && make CFLAGS="-Wno-error" \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && rm /usr/local/lib/*.a \
 # && rm -r /usr/local/include \
 ;

FROM scratch
LABEL org.opencontainers.image.authors="exe-dealer@yandex.kz"
COPY --from=0 / /
RUN adduser --uid 70 --system --disabled-password --home /var/lib/postgresql postgres
USER postgres
WORKDIR /var/lib/postgresql
ENV PGDATA=/var/lib/postgresql/data/pg18
EXPOSE 5432
CMD ["postgres"]

RUN mkdir -p $PGDATA \
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

VOLUME /var/lib/postgresql/data
