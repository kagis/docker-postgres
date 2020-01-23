FROM alpine:3.11 AS geos
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/libgeos/geos/archive/3.8.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
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

FROM alpine:3.11 AS proj
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/OSGeo/PROJ/archive/6.2.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
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

FROM alpine:3.11 AS postgres_base
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgres/postgres/archive/REL_11_4.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
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
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5-dev \
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
  --with-llvm LLVM_CONFIG=/usr/lib/llvm5/bin/llvm-config \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# postgis
COPY --from=geos /usr/local /usr/local
COPY --from=proj /usr/local /usr/local
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/postgis/postgis/archive/2.5.3.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
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
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5-dev \
 \
 && cd /tmp/postgis-* \
 && ./autogen.sh \
 && ./configure --without-raster \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_cron
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/citusdata/pg_cron/archive/v1.2.0.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
  build-base \
  clang \
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5-dev \
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
 && wget -qO- https://github.com/kagis/pg_json_decoding/archive/b34e9779dfbd484d3ed09134ac33c1046da5a7bc.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
  build-base \
  clang \
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5-dev \
 \
 && cd /tmp/pg_json_decoding-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

# pg_json_log
RUN set -x \
 && cd /tmp \
 && wget -qO- https://github.com/kagis/pg_json_log/archive/68130f628cf112534a1ff713eb50eb2eb714cd58.tar.gz | tar xz \
 && apk add --no-cache --virtual .build-deps \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
  build-base \
  clang \
  openssl-dev \
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5-dev \
 \
 && cd /tmp/pg_json_log-* \
 && make \
 && make install \
 && apk del .build-deps \
 && rm -r /tmp/*

RUN set -x \
 && apk add --no-cache \
  --repositories-file /dev/null \
  --repository https://mirror.ps.kz/alpine/v3.11/main \
  libxml2 \
  libxslt \
  python3 \
  protobuf-c \
  json-c \
  icu \
  openssl \
  --repository https://mirror.ps.kz/alpine/v3.11/community \
  llvm5 \

FROM scratch
COPY --from=postgres_base / /
ENV PGDATA=/var/lib/postgresql/data
EXPOSE 5432
USER postgres
