#!/bin/sh
set -e

PGOPTS="-c config_file=conf/postgresql.conf $PGOPTS"

pg_ctl -w start --timeout 3600 -o "$PGOPTS -c log_statement=all"

find migrations -type d -mindepth 1 -maxdepth 1 -exec basename {} ';' \
| xargs -I %DB% psql -d %DB% --no-align --tuples-only --field-separator ' ' -P null=. \
  -c "SELECT current_database(), current_setting('migration.latest', true)" \
| xargs -rn2 sh -c 'ls -1 "migrations/$0" | awk -v DB="$0" -v M="$1" "/\.sql\$/ && \$0 > M { print DB, \$0 }"' \
| xargs -rn2 sh -c $' \
  psql -d "$0" -v ON_ERROR_STOP=1 --single-transaction \
    -f "migrations/$0/$1" \
    -c "ALTER DATABASE \"$0\" SET migration.latest = \'$1\'" '

pg_ctl -w stop

# теперь, после выполения миграций, разрешаем конектиться к постгресу
PGOPTS="$PGOPTS -c listen_addresses=0.0.0.0"

if [ $MIGRATION_FAILED ]; then
  # если миграции не выполнились успешно, то запрещаем подключаться
  # к постгресу всем пользователям кроме `postgres` чтобы можно
  # было подконектиться и починить руками
  PGOPTS="$PGOPTS -c hba_file=conf/pg_hba.on_migration_fail.conf"
fi

exec postgres $PGOPTS
