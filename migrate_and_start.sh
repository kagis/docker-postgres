#!/bin/sh
set -e

pg_ctl --silent --wait start --timeout 3600 \
  -o "-c config_file=conf/postgresql.on_migration.conf"

export MIGRATION_FAILED

find migrations -type d -mindepth 1 -maxdepth 1 -exec basename {} ';' \
| xargs -I %DB% psql -d %DB% --no-align --tuples-only --field-separator ' ' -P null=. \
  -c "SELECT current_database(), current_setting('migration.latest', true)" \
| xargs -rn2 sh -c 'ls -1 "migrations/$0" | awk -v DB="$0" -v M="$1" "/\.sql$/ && \$0 > M { print DB, \$0 }"' \
| xargs -rn2 sh -c $'
  psql -d "$0" -v ON_ERROR_STOP=1 --single-transaction \
    -f "migrations/$0/$1" \
    -c "ALTER DATABASE \"$0\" SET migration.latest = \'$1\'" \
  || exit 255' \
|| MIGRATION_FAILED=1

pg_ctl --silent --wait stop

if [ $MIGRATION_FAILED ]; then
  exec postgres -c config_file=conf/postgresql.on_migration_fail.conf $PGOPTS
fi

exec postgres -c config_file=conf/postgresql.conf $PGOPTS
