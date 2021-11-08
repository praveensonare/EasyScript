#!/bin/bash

ERRORCODE=1

set -e

export PGPASSWORD="DaVinci"
PG_PATH="/Library/PostgreSQL"

PG_OLD_VER="9.5"
PG_OLD_HOME="$PG_PATH/${PG_OLD_VER}"
PG_OLD_BIN="${PG_OLD_HOME}/bin"
PG_OLD_DATA="${PG_OLD_HOME}/data"

PG_VER="13"
PG_HOME="$PG_PATH/${PG_VER}"
PG_BIN="${PG_HOME}/bin"
PG_DATA="${PG_HOME}/data"
PG_INSTALLER="${PG_HOME}/installer/server"

if [ "$UID" -ne "0" ]
then
    echo "!!! must be run as super-user" 1>&2
    exit 1
fi

TMP=`mktemp -d`
echo "$TMP"

_cleanup()
{
    rm -rf "$TMP"

    trap "" 0 INT ERR

    if [ ${ERRORCODE} == 0 ]
    then
        echo "Upgrade completed successfully"
        exit 0
    else
        echo "!!! install failed"
        exit ${ERRORCODE}
    fi
}

trap _cleanup 0 INT ERR

_stop_running_postgresql() #arg1 = version
{
    echo "+++ check running postgres"
    VERSION=${1}
    DATA="${PG_PATH}/${VERSION}/data/"
    BIN="${PG_PATH}/${VERSION}/bin/"
    if su - postgres -c "ls ${DATA}/postmaster.pid" >& /dev/null
    then
        echo "    +++ postgres ${VERSION} is running - stopping..."
        sudo su - postgres -c "${BIN}/pg_ctl stop -D ${DATA}"
    fi

    if launchctl list | grep -q "com.edb.launchd.postgresql-${VERSION}$" > /dev/null
    then
        echo "+++ unload postgres ${VERSION}"
        launchctl unload /Library/LaunchDaemons/com.edb.launchd.postgresql-"${VERSION}".plist

        sleep 2

        # removing .plist file to ensure old server does not restart on system boot.
        rm -rf /Library/LaunchDaemons/com.edb.launchd.postgresql-"${VERSION}".plist
    fi
}

_start_running_postgresql() #arg1 = version
{
    VERSION=${1}
    DATA="${PG_PATH}/${VERSION}/data/"
    BIN="${PG_PATH}/${VERSION}/bin/"
    echo "+++ check running postgres [${VERSION}] DATA=${DATA}"
    if ! su - postgres -c "ls ${DATA}/postmaster.pid" >& /dev/null
    then
        echo "    +++ postgres ${VERSION} is stopped - starting..."
        sudo su - postgres -c "${BIN}/pg_ctl start -D ${DATA}"

        # server takes some time to come online so some delay is needed to execute any command/query
        sleep 2
    fi
}

_reindex_database() #arg1 = version
{
    VERSION=${1}
    DATA="${PG_PATH}/${VERSION}/data/"
    BIN="${PG_PATH}/${VERSION}/bin/"

    _start_running_postgresql ${VERSION}
    ${BIN}/reindexdb --all --username postgres
}

_install_postgresql()
{
    if [ -d ${PG_BIN} ]
    then
        echo "    --- postgresql is already installed - skipping step"
        return
    fi

    ERRORCODE=2
    rm -rf "$TMP/postgresql"
    mkdir "$TMP/postgresql"
    unzip -q postgresql.zip -d "$TMP/postgresql"

    "$TMP/postgresql/"*".app/Contents/MacOS/installbuilder.sh" --mode unattended --debuglevel 4 --create_shortcuts 0 --unattendedmodeui none --superpassword DaVinci
    rm -rf "$TMP/postgresql"

    ERRORCODE=3
    echo "+++ set sysctls" # try to be a good citizen & only change parameters if required
    [ $(sysctl -n kern.sysv.shmmax) -lt 33554432 ] && echo kern.sysv.shmmax=33554432 >> /etc/sysctl.conf && sysctl -w kern.sysv.shmmax=33554432
    [ $(sysctl -n kern.sysv.shmmin) -gt 1 ]        && echo kern.sysv.shmmin=1        >> /etc/sysctl.conf && sysctl -w kern.sysv.shmmin=1
    [ $(sysctl -n kern.sysv.shmmni) -lt 256 ]      && echo kern.sysv.shmmni=256      >> /etc/sysctl.conf
    [ $(sysctl -n kern.sysv.shmseg) -lt 64 ]       && echo kern.sysv.shmseg=64       >> /etc/sysctl.conf && sysctl -w kern.sysv.shmseg=64
    [ $(sysctl -n kern.sysv.shmall) -lt 8192 ]     && echo kern.sysv.shmall=8192     >> /etc/sysctl.conf && sysctl -w kern.sysv.shmall=8192

    sudo dscl . -delete /Users/postgres AuthenticationAuthority

    echo "+++ update configuration"
    TMP_EXT=$$
    su - postgres -c "sed -e '/escape_string_warning/s/on$/off/' ${PG_DATA}/postgresql.conf | sed -e '/escape_string_warning/s/^#//' > ${PG_DATA}/postgresql.conf.${TMP_EXT} && mv ${PG_DATA}/postgresql.conf.${TMP_EXT} ${PG_DATA}/postgresql.conf"
}

_migrate_data()
{
    OLD_PATH="$1"
    OLD_BIN="${OLD_PATH}/bin"
    OLD_DATA="${OLD_PATH}/data"

    NEW_PATH="$2"
    NEW_BIN="${NEW_PATH}/bin"
    NEW_DATA="${NEW_PATH}/data"

    export PGPASSWORD="DaVinci"

    "${OLD_BIN}"/pg_ctl stop -D ${OLD_DATA}
    "${NEW_BIN}"/pg_ctl stop -D ${NEW_DATA}

    #get methods
    OLD_HBA_FILE="${OLD_DATA}/pg_hba.conf"
    lines=($(grep '::1' ${OLD_HBA_FILE} | grep -v 'replication'))
    OLD_METHOD=${lines[4]}

    NEW_HBA_FILE="${NEW_DATA}/pg_hba.conf"
    lines=($(grep '::1' ${NEW_HBA_FILE} | grep -v 'replication'))
    NEW_METHOD=${lines[4]}

    #CREATING BACKUP
    HBA_CONF="${NEW_DATA}/pg_hba.conf"
    HBA_CONF_BAK="${HBA_CONF}.bak"
    mv ${HBA_CONF} ${HBA_CONF_BAK}

    #creating a trust file FOR NON SECURE CONNECTION, DB is OFFLINE
    echo "# TYPE  DATABASE        USER            ADDRESS                 METHOD" > ${HBA_CONF}
    echo "local   all             all                                     trust" >> ${HBA_CONF}
    echo "host    all             all             127.0.0.1/32            trust" >> ${HBA_CONF}

    #MIGRATE DATA
    ${NEW_BIN}/pg_upgrade -d ${OLD_DATA} -D ${NEW_DATA} --user postgres -b ${OLD_BIN} -B ${NEW_BIN}

    ${NEW_BIN}/pg_ctl -D ${NEW_DATA} start
    ${NEW_BIN}/psql --host 127.0.0.1 --username postgres -c "ALTER USER postgres WITH PASSWORD 'DaVinci'"

    if ls reindex_hash.sql >& /dev/null
    then
        ${NEW_BIN}/psql --host 127.0.0.1 --username postgres < reindex_hash.sql
    fi

    rm -rf ${HBA_CONF}

    OLD_CONF_FILE="${HBA_CONF}_method"
    sed -e "s/$OLD_METHOD/${NEW_METHOD}/" ${OLD_HBA_FILE} > $OLD_CONF_FILE

    while read line; do
        if echo "$line" | grep -v "local\|127.0.0.1\|::1"; then
          echo "$line" >> ${HBA_CONF}
        fi
    done < ${OLD_CONF_FILE}

    while read line; do
        if echo "$line" | grep -v "#\|^$"; then
          echo "$line" >> ${HBA_CONF}
        fi
    done < ${HBA_CONF_BAK}

    ${NEW_BIN}/pg_ctl -D ${NEW_DATA} restart

    #cleanup -- removing autogenerated files and temp files
    rm -rf reindex_hash.sql
    rm -rf delete_old_cluster.sh
    rm -rf ${HBA_CONF_BAK}
    rm -rf ${OLD_CONF_FILE}
}

_upgrade()
{
    _reindex_database ${PG_OLD_VER}
    _stop_running_postgresql ${PG_OLD_VER}
    _install_postgresql

    migrate_data=$(declare -f _migrate_data)
    sudo su - postgres -c "$migrate_data; _migrate_data ${PG_PATH}/${PG_OLD_VER} ${PG_PATH}/${PG_VER}"
}

_upgrade

ERRORCODE=0
