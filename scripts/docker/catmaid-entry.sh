#!/bin/bash

# Remove quotes around a string
sanitize() { echo "$1" | sed "s/^[\"']\?\(.*[^\"']\)[\"']\?$/\1/"; }

# Get environment configuration or use defaults if unavailable.
DB_HOST=$(sanitize "${DB_HOST:-localhost}")
DB_PORT=$(sanitize "${DB_PORT:-5432}")
DB_NAME=$(sanitize "${DB_NAME:-catmaid}")
DB_USER=$(sanitize "${DB_USER:-catmaid_user}")
DB_PASS=$(sanitize "${DB_PASS:-catmaid_password}")
DB_CONNECTIONS=$(sanitize "${DB_CONNECTIONS:-50}")
DB_CONF_FILE=$(sanitize "${DB_CONF_FILE:-"/etc/postgresql/11/main/postgresql.conf"}")
DB_FORCE_TUNE=$(sanitize "${DB_FORCE_TUNE:-false}")
DB_TUNE=$(sanitize "${DB_TUNE:-true}")
DB_FIXTURE=$(sanitize "${DB_FIXTURE:-false}")
AVAILABLE_MEMORY=`awk '/MemTotal/ { printf "%.3f \n", $2/1024 }' /proc/meminfo`
INSTANCE_MEMORY=${INSTANCE_MEMORY:-$AVAILABLE_MEMORY}
CM_INITIAL_ADMIN_USER=$(sanitize "${CM_INITIAL_ADMIN_USER:-"admin"}")
CM_INITIAL_ADMIN_PASS=$(sanitize "${CM_INITIAL_ADMIN_PASS:-"admin"}")
CM_INITIAL_ADMIN_EMAIL=$(sanitize "${CM_INITIAL_ADMIN_EMAIL:-"admin@localhost.local"}")
CM_INITIAL_ADMIN_FIRST_NAME=$(sanitize "${CM_INITIAL_ADMIN_FIRST_NAME:-"Super"}")
CM_INITIAL_ADMIN_LAST_NAME=$(sanitize "${CM_INITIAL_ADMIN_LAST_NAME:-"User"}")
CM_DEBUG=$(sanitize "${CM_DEBUG:-false}")
CM_EXAMPLE_PROJECTS=$(sanitize "${CM_EXAMPLE_PROJECTS:-true}")
# This is expected to be a JSON project definition like it is exported through
# the /projects/export API.
CM_INITIAL_PROJECTS=${CM_INITIAL_PROJECTS:-""}
CM_INITIAL_PROJECTS_IMPORT_PARAMS=${CM_INITIAL_PROJECTS_IMPORT_PARAMS:-""}
CM_IMPORTED_SKELETON_FILE_MAXIMUM_SIZE=$(sanitize "${CM_IMPORTED_SKELETON_FILE_MAXIMUM_SIZE:-""}")
CM_HOST=$(sanitize "${CM_HOST:-0.0.0.0}")
CM_PORT=$(sanitize "${CM_PORT:-8000}")
CM_FORCE_CONFIG_UPDATE=$(sanitize "${CM_FORCE_CONFIG_UPDATE:-false}")
CM_WRITEABLE_PATH=$(sanitize "${CM_WRITEABLE_PATH:-"'/tmp'"}")
CM_NODE_LIMIT=$(sanitize "${CM_NODE_LIMIT:-10000}")
CM_NODE_PROVIDERS=$(sanitize "${CM_NODE_PROVIDERS:-"['postgis2d']"}")
CM_SUBDIRECTORY=$(sanitize "${CM_SUBDIRECTORY:-""}")
CM_CSRF_TRUSTED_ORIGINS=$(sanitize "${CM_CSRF_TRUSTED_ORIGINS:-""}")
CM_FORCE_CLIENT_SETTINGS=$(sanitize "${CM_FORCE_CLIENT_SETTINGS:-false}")
CM_CLIENT_SETTINGS=${CM_CLIENT_SETTINGS:-""}
CM_SERVER_SETTINGS=${CM_SERVER_SETTINGS:-""}
TIMEZONE=`readlink /etc/localtime | sed "s/.*\/\(.*\)$/\1/"`
PG_VERSION='12'

# Check if the first argument begins with a dash. If so, prepend "platform" to
# the list of arguments.
if [ "${1:0:1}" = '-' ]; then
    set -- platform "$@"
fi

init_catmaid () {
  PGBIN="/usr/lib/postgresql/${PG_VERSION}/bin"
  echo "Wait until database $DB_HOST:$DB_PORT is ready..."
  until su postgres -c "${PGBIN}/pg_isready -h '${DB_HOST}' -p ${DB_PORT} -q; exit \$?"
  do
      sleep 1
  done

  # Wait to avoid "panic: Failed to open sql connection pq: the database system is starting up"
  sleep 1

  if [ -f "/git-commit" ]; then
    CM_VERSION=$(cat /git-commit);
    echo "CATMAID Git commit: ${CM_VERSION}"
  else
    echo "No detailed CATMAID version information found"
  fi

  echo "Loading virtualenv"
  source /usr/share/virtualenvwrapper/virtualenvwrapper.sh
  workon catmaid

  if [ ! -f /home/django/projects/mysite/settings.py ] || ["$CM_FORCE_CONFIG_UPDATE" = true]; then
    echo "Setting up CATMAID"

    cp /home/django/configuration.py.example /home/django/configuration.py
    sed -i -e "s?^\(abs_catmaid_path = \).*?\1'/home'?g" /home/django/configuration.py
    sed -i -e "s?^\(abs_virtualenv_python_library_path = \).*?\1'/opt/virtualenvs/catmaid/local/lib/python3.6/site-packages'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_database_host = \).*?\1'${DB_HOST}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_database_port = \).*?\1'${DB_PORT}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_database_name = \).*?\1'${DB_NAME}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_database_username = \).*?\1'${DB_USER}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_database_password = \).*?\1'${DB_PASS}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_timezone = \).*?\1'${TIMEZONE}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_servername = \).*?\1'*'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_subdirectory = \).*?\1'${CM_SUBDIRECTORY}'?g" /home/django/configuration.py
    sed -i -e "s?^\(catmaid_writable_path = \).*?\1'${CM_WRITEABLE_PATH}'?g" /home/django/configuration.py
    cd /home/django && python create_configuration.py
    mkdir -p /home/django/static
  fi

  cd /home/django/projects

  # General settings config
  if [ ! -z "${CM_SERVER_SETTINGS}" ]; then
    echo -e "Updating settings.py\n${CM_SERVER_SETTINGS}"
    echo -e "\n${CM_SERVER_SETTINGS}" >> mysite/settings.py
  fi

  # Update debug setting
  sed -i "/^\(DEBUG = \).*/d" mysite/settings.py
  catmaid_debug=False
  if [ "$CM_DEBUG" = true ]; then
    catmaid_debug=True
  fi
  echo "Setting DEBUG = ${catmaid_debug}"
  echo "DEBUG = ${catmaid_debug}" >> mysite/settings.py

  # Update maximum import size setting
  sed -i "/^\(IMPORTED_SKELETON_FILE_MAXIMUM_SIZE = \).*/d" mysite/settings.py
  if [ ! -z "${CM_IMPORTED_SKELETON_FILE_MAXIMUM_SIZE}" ]; then
    echo "Setting IMPORTED_SKELETON_FILE_MAXIMUM_SIZE = ${CM_IMPORTED_SKELETON_FILE_MAXIMUM_SIZE}"
    echo "IMPORTED_SKELETON_FILE_MAXIMUM_SIZE = ${CM_IMPORTED_SKELETON_FILE_MAXIMUM_SIZE}" >> mysite/settings.py
  fi

  # Update CSRF information
  sed -i "/^\(CSRF_TRUSTED_ORIGINS = \).*/d" mysite/settings.py
  if [ ! -z "${CM_CSRF_TRUSTED_ORIGINS}" ]; then
    echo "Setting CSRF_TRUSTED_ORIGINS = ${CM_CSRF_TRUSTED_ORIGINS}"
    echo "CSRF_TRUSTED_ORIGINS = ${CM_CSRF_TRUSTED_ORIGINS}" >> mysite/settings.py
  fi

  # Update node limit
  sed -i "/^\(NODE_LIST_MAXIMUM_COUNT = \).*/d" mysite/settings.py
  echo "Setting NODE_LIST_MAXIMUM_COUNT = ${CM_NODE_LIMIT}"
  echo "NODE_LIST_MAXIMUM_COUNT = ${CM_NODE_LIMIT}" >> mysite/settings.py

  # Update node provider
  sed -i "/^\(NODE_PROVIDERS = \).*/d" mysite/settings.py
  echo "Setting NODE_PROVIDERS = ${CM_NODE_PROVIDERS}"
  echo "NODE_PROVIDERS = ${CM_NODE_PROVIDERS}" >> mysite/settings.py

  # Set initially client-setting, use raw string to not have Python interpret
  # escaped characters.
  sed -i "/^\(CLIENT_SETTINGS = \).*/d" mysite/settings.py
  echo "Setting CLIENT_SETTINGS = r'${CM_CLIENT_SETTINGS}'"
  echo "CLIENT_SETTINGS = r'${CM_CLIENT_SETTINGS}'" >> mysite/settings.py
  sed -i "/^\(FORCE_CLIENT_SETTINGS = \).*/d" mysite/settings.py
  if [ "$CM_FORCE_CLIENT_SETTINGS" = true ]; then
    echo "Setting FORCE_CLIENT_SETTINGS = True"
    echo "FORCE_CLIENT_SETTINGS = True" >> mysite/settings.py
  else
    echo "Setting FORCE_CLIENT_SETTINGS = False"
    echo "FORCE_CLIENT_SETTINGS = False" >> mysite/settings.py
  fi

  # Create database and databsae user if not yet present. This should only
  # happen if the database is not run in a separete container.
  echo "Testing database access"
  if ! PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -w; then
    echo "Initialize CATMAID database"
    /home/scripts/createuser.sh ${DB_NAME} ${DB_USER} ${DB_PASS} | runuser -l postgres -c 'psql -h "${DB_HOST}" -p "${DB_PORT}"'
  fi

  # Migrate the database, collect static files and create a superuser.
  echo "Migrating databse"
  python manage.py migrate --noinput
  echo "Updating static files"
  python manage.py collectstatic --clear --noinput

  # The additional new lines are needed to end the input stream. This will try
  # to read the environment variables CM_INITIAL_ADMIN_USER,
  # CM_INITIAL_ADMIN_PASS and CM_INITIAL_ADMIN_EMAIL,
  # CM_INITIAL_ADMIN_FIRST_NAME, CM_INITIAL_ADMIN_LAST_NAME.
  echo "Ensuring existence of super user"
  printf '\n\n' | cat /home/scripts/docker/create_superuser.py - | python manage.py shell

  if [ "$CM_EXAMPLE_PROJECTS" = true ]; then
    python manage.py catmaid_insert_example_projects --user=1
  fi

  if [ ! -z "$CM_INITIAL_PROJECTS" ]; then
    echo "Initializig project configuration";
    echo "$CM_INITIAL_PROJECTS" | python manage.py catmaid_import_projects $CM_INITIAL_PROJECTS_IMPORT_PARAMS
  fi

  # Make sure uWSGI runs on the correct port
  echo "Configuring uWSGI to run on socket ${CM_HOST}:${CM_PORT}"
  sed -i "s/socket = .*/socket = ${CM_HOST}:${CM_PORT}/g" /home/scripts/docker/uwsgi-catmaid.ini

  echo "Starting CATMAID"
  supervisord -n -c /etc/supervisor/supervisord.conf
}

if [ "$1" = 'standalone' ]; then
  if ! grep -Fxq "local ${DB_NAME} ${DB_USER} md5" "${DB_CONF_FILE/postgresql.conf/}pg_hba.conf"
  then
      echo "Updating Postgres access configuration in file ${DB_CONF_FILE/postgresql.conf/}pg_hba.conf"
      sed -i "/# DO NOT DISABLE!/ilocal ${DB_NAME} ${DB_USER} md5" "${DB_CONF_FILE/postgresql.conf/}pg_hba.conf"
  fi

  if [ "$DB_TUNE" = true ]; then
  echo "Tuning Postgres server configuration"
    CONNECTIONS=${DB_CONNECTIONS} CONF_FILE="${DB_CONF_FILE}" FORCE_PGTUNE=${DB_FORCE_TUNE} python /home/scripts/database/pg_tune.py
  fi

  service postgresql restart

  if [ "$DB_FIXTURE" = true ]; then
    echo "Initializing database with data from stdin";
    first_byte=$(dd bs=1 count=1 2>/dev/null | od -t o1 -A n)
    if [ -z "$first_byte" ]; then
      # If stdin is empty
      echo "- Error: no data in stdin"
      exit 1
    else
      {
        printf "\\${first_byte# }"
        cat
      } | {
        # If stdin is not empty
        su postgres -c "psql"
      }
    fi

    echo "Analyzing all databases";
    su postgres -c "vacuumdb -a -z"
  fi

  echo "Linking /home/scripts/docker/nginx-catmaid.conf"
  rm -f /etc/nginx/sites-enabled/default
  ln -sf /home/scripts/docker/nginx-catmaid.conf /etc/nginx/sites-enabled/

  echo "Starting Nginx"
  service nginx start
  init_catmaid
elif [ "$1" = 'platform' ]; then
  init_catmaid
else
    exec "$@"
fi
