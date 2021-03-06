FROM alpine:3.12 AS geos
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/libgeos/geos/archive/3.8.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  automake \
  autoconf \
  libtool \
 \
 && cd /tmp/geos-* \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

FROM alpine:3.12 AS proj_gdal
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/PROJ/archive/6.3.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  autoconf \
  automake \
  libtool \
  sqlite \
  sqlite-dev \
 \
 && cd /tmp/PROJ-* \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/gdal/archive/v3.1.4.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  linux-headers \
  sqlite-dev \
 \
 && cd /tmp/gdal-*/gdal \
 && ./configure --without-libtool --enable-lto \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

FROM alpine:3.12 AS postgres_base
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_13_0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
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
  llvm10-dev \
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
  --with-llvm LLVM_CONFIG=/usr/lib/llvm10/bin/llvm-config \
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
 && wget -qO- https://github.com/postgis/postgis/archive/3.0.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
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
  clang-dev \
  llvm10-dev \
 \
 && cd /tmp/postgis-* \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
 && make comments-install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pgsql-http
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/pramsey/pgsql-http/archive/v1.3.1.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  curl-dev \
  clang \
  llvm10-dev \
 \
 && cd /tmp/pgsql-http-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/v1.3.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  clang \
  llvm10-dev \
 \
 && cd /tmp/pg_cron-* \
 # https://github.com/citusdata/pg_cron/issues/9#issuecomment-269188155
 && sed -e s/-Werror//g -i Makefile \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_json_decoding
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/kagis/pg_json_decoding/archive/v20201030.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  clang \
  llvm10-dev \
 \
 && cd /tmp/pg_json_decoding-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_json_log
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/kagis/pg_json_log/archive/v20201030.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  build-base \
  clang \
  openssl-dev \
  llvm10-dev \
 \
 && cd /tmp/pg_json_log-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && apk add --no-cache \
  # --repositories-file /dev/null \
  # --repository https://mirror.ps.kz/alpine/v3.12/main \
  libxml2 \
  libxslt \
  python3 \
  protobuf-c \
  json-c \
  icu \
  openssl \
  libcurl \
  llvm10 \
 && adduser --uid 70 \
   --disabled-password \
   --home /var/lib/postgresql \
   --no-create-home \
   postgres \
 && install -o postgres -g postgres -m 700 -d \
  /var/lib/postgresql/data \
  /var/lib/postgresql/conf \
  /var/lib/postgresql/init

COPY conf /var/lib/postgresql/conf
COPY migrate_and_start.sh /var/lib/postgresql/

FROM scratch
MAINTAINER Vladislav Nezhutin <exe-dealer@yandex.ru>
COPY --from=postgres_base / /
# FIXME hub.docker.com does not preserve ownership
RUN chown -R postgres:postgres /var/lib/postgresql
WORKDIR /var/lib/postgresql
ENV PGDATA=/var/lib/postgresql/data
USER postgres
EXPOSE 5432
CMD ["/bin/sh", "migrate_and_start.sh"]

ONBUILD COPY . ./
ONBUILD RUN set -x \
 && initdb \
 && rm $PGDATA/postgresql.conf $PGDATA/pg_hba.conf \
 && pg_ctl --silent --wait start -o "-c config_file=conf/postgresql.on_migration.conf" \
 && (cd init && psql -v ON_ERROR_STOP=1 -f init.sql) \
 && find migrations -type f -mindepth 2 -maxdepth 2 -name '*.sql' \
  # find latest migration for each db
  | sort -r | awk -F/ '{ print $3, $2 }' | uniq -f1 | awk '{ print $2, $1 }' \
  | xargs -rn2 printf "ALTER DATABASE \"%s\" SET migration.latest = '%s';\n" \
  | psql -v ON_ERROR_STOP=1 \
 && pg_ctl --silent --wait stop
ONBUILD VOLUME $PGDATA
