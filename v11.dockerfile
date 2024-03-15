FROM alpine:3.19.1

RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_11_22.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base autoconf automake libtool bison flex linux-headers \
  readline-dev python3-dev libxslt-dev icu-dev openssl-dev clang16-dev llvm16-dev \
 && cd /tmp/postgres-* \
 && CLANG=/usr/lib/llvm16/bin/clang ./configure \
  --prefix=/usr/local \
  --with-libxml \
  --with-libxslt \
  --with-python \
  --with-icu \
  --with-openssl \
  --with-llvm LLVM_CONFIG=/usr/lib/llvm16/bin/llvm-config \
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
 && wget -qO- https://github.com/OSGeo/PROJ/archive/6.3.2.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base autoconf automake libtool sqlite-dev \
 && cd /tmp/PROJ-* \
 && sed -i '1s;^;#include <cstdint>\n;' src/proj_json_streaming_writer.hpp \
 && ./autogen.sh \
 && ./configure \
 && make \
 && make install \
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
 && wget -qO- https://github.com/postgis/postgis/archive/2.5.11.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  build-base autoconf automake libtool libcurl tiff \
  libxslt-dev json-c-dev protobuf-c-dev sqlite-dev clang16 llvm16-dev \
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
 && apk add --no-cache --virtual .build-deps build-base curl-dev clang16 llvm16-dev \
 && cd /tmp/pgsql-http-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/v1.2.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base clang16 llvm16-dev \
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
 && wget -qO- https://github.com/kagis/pg_json_decoding/archive/77b3f82094e6f590eb01d951d023d2736947abf6.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base clang16 llvm16-dev \
 && cd /tmp/pg_json_decoding-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_json_log
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/kagis/pg_json_log/archive/68130f628cf112534a1ff713eb50eb2eb714cd58.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps build-base clang16 llvm16-dev openssl-dev \
 && cd /tmp/pg_json_log-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && apk add --no-cache readline libxslt python3 protobuf-c json-c icu openssl curl tiff llvm16 tzdata jq \
 && adduser --uid 70 --disabled-password --home /var/lib/postgresql postgres \
 && install -o postgres -g postgres -m 700 -d \
  /var/lib/postgresql/data \
  /var/lib/postgresql/conf \
  /var/lib/postgresql/init

COPY conf /var/lib/postgresql/conf
COPY migrate_and_start.sh /var/lib/postgresql/

FROM scratch
MAINTAINER Vladislav Nezhutin <exe-dealer@yandex.ru>
COPY --from=0 / /
USER postgres
WORKDIR /var/lib/postgresql
ENV PGDATA=/var/lib/postgresql/data
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
