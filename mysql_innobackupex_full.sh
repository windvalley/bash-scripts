#!/bin/bash
# mysql_innobackupex_full.sh
# for mysql5.1,5.5,5.6
# 2015/12/2
#
#********** crontab e.g. **********
# 0 1 * * 0  sh /path/mysql_innobackupex_full.sh
# 0 1 * * 1,2,3,4,5,6 sh /path/mysql_innobackupex_incremental.sh
#**********************************


XTRA_BIN_DIR=/usr/local/src/percona-xtrabackup-2.3.2-Linux-x86_64/bin
XTRA_BIN_DIR_FOR51=/usr/local/src/percona-xtrabackup-2.0.8/bin
BACKUP_DBS="db1 db2"
BACKUP_DIR=/backups/mysql
FULL_BACKUP_DIR=
BACKUP_TMP_LOG=/tmp/backup.log

MYSQL_BASEDIR=/usr/local/mysql5627
MYSQL_ETC_FILE=$MYSQL_BASEDIR/etc/my.cnf
MYSQL_USER=root
MYSQL_PASSWORD=mysql
MYSQL_SOCKET=$MYSQL_BASEDIR/tmp/mysql.sock
MYSQL_VERSION=$($MYSQL_BASEDIR/bin/mysql -V |
    grep -Eo 'Distrib [0-9.]+' | awk -F. '{print $2}')


[[ -z "$FULL_BACKUP_DIR" ]] &&
    FULL_BACKUP_DIR=$BACKUP_DIR/week$(date +%V)/full_$(date +%Y%m%d)

[[ -s "$BACKUP_TMP_LOG" ]] && >"$BACKUP_TMP_LOG"

log(){
    time=$(date +%F" "%T)
    echo "$time [$1]: $2" >>$BACKUP_TMP_LOG 2>&1
}

pipelog(){
    while read -r line;do
        time=$(date +%F" "%T)
        echo "$line"|sed "s/^/$time [$1]: /" >>$BACKUP_TMP_LOG 2>&1
    done
}

full_backup(){
    bin_dir=$1
    slave_or_no=$( $MYSQL_BASEDIR/bin/mysql -u$MYSQL_USER -p$MYSQL_PASSWORD \
        -NBe "show slave status" 2>/dev/null| grep -v "Logging to file" )

    [ -z "$slave_or_no" ] && SlaveOption="" || SlaveOption="--slave-info"
    export PATH="$PATH:$bin_dir:$MYSQL_BASEDIR/bin"
    log "NOTE" "use innobackupex: $bin_dir/innobackupex."
    log "NOTE" "full backup mysql: $MYSQL_BASEDIR."
    log "NOTE" "backup to: $FULL_BACKUP_DIR."

    (
    exec 2>&1
    "$bin_dir"/innobackupex \
        --defaults-file="$MYSQL_ETC_FILE" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --socket="$MYSQL_SOCKET" \
        $SlaveOption \
        --no-timestamp \
        --databases="$BACKUP_DBS" \
        "$FULL_BACKUP_DIR"
    ) | pipelog "innobackupex full-backup"
}

[ -d "$FULL_BACKUP_DIR" ] && {
    log "ERROR" "$FULL_BACKUP_DIR already exists. Aborting!"
    exit 1
}

[[ ! -d "${FULL_BACKUP_DIR%/*}" ]] && mkdir -p "${FULL_BACKUP_DIR%/*}"

if [[ "$MYSQL_VERSION" -eq 1 ]]; then
    full_backup $XTRA_BIN_DIR_FOR51
else
    full_backup $XTRA_BIN_DIR
fi

mv $BACKUP_TMP_LOG "$FULL_BACKUP_DIR"

tail -1 "${FULL_BACKUP_DIR}"/backup.log | grep -q "completed OK!" &&
    echo "success." || echo "failed."


exit 0
