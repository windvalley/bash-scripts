#!/bin/bash
# mysql_innobackupex_incremental.sh
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
BACKUP_DIR="/backups/mysql"
BACKUP_TMP_LOG=/tmp/backup.log
INCREMENTAL_BASEDIR=/backups/mysql/week49/increment1
INCREMENTAL=/backups/mysql/week49/increment2

# value: day of week (0..6), 0 is Sunday
FULL_BACKUP_DAY=0
INCRE_START_BACKUP_DAY=$(("$FULL_BACKUP_DAY"+1))

MYSQL_BASEDIR=/usr/local/mysql5627
MYSQL_ETC_FILE=$MYSQL_BASEDIR/etc/my.cnf
MYSQL_USER=root
MYSQL_PASSWORD=mysql
MYSQL_SOCKET=$MYSQL_BASEDIR/tmp/mysql.sock
MYSQL_VERSION=$($MYSQL_BASEDIR/bin/mysql -V |
    grep -Eo 'Distrib [0-9.]+'|awk -F. '{print $2}')
DAYTH=$(date +%w)


[[ -s "$BACKUP_TMP_LOG" ]] && >$BACKUP_TMP_LOG

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

incremental_backup(){
    bin_dir=$1
    SLAVE_OR_NO=$($MYSQL_BASEDIR/bin/mysql -u$MYSQL_USER -p$MYSQL_PASSWORD \
        -NBe "show slave status" 2>/dev/null | grep -v "Logging to file" )

    [[ -z "$SLAVE_OR_NO" ]] && slave_option="" || slave_option="--slave-info"

    export PATH="$PATH:$bin_dir:$MYSQL_BASEDIR/bin"
    log "NOTE" "use innobackupex: $bin_dir/innobackupex."
    log "NOTE" "incremental backup mysql: $MYSQL_BASEDIR."
    log "NOTE" "--incremental-basedir: $INCREMENTAL_BASEDIR"
    log "NOTE" "--incremental: $INCREMENTAL."

    (
    exec 2>&1
    "${bin_dir}"/innobackupex \
        --defaults-file="$MYSQL_ETC_FILE" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --socket="$MYSQL_SOCKET" \
        --databases="$BACKUP_DBS" \
        $slave_option \
        --no-timestamp \
	--incremental-basedir="$INCREMENTAL_BASEDIR" \
	--incremental \
	"$INCREMENTAL"
    ) | pipelog "innobackupex incremental-backup"
}

[[ $DAYTH -eq $FULL_BACKUP_DAY ]] && {
    log "ERROR" "Today is $FULL_BACKUP_DAY day of a week,and excute full backup, not incremental backup."
    exit 1
}

[[ -z "$INCREMENTAL_BASEDIR" ]] && {
    if [[ $DAYTH -eq $INCRE_START_BACKUP_DAY ]]; then
        INCREMENTAL_BASEDIR=$BACKUP_DIR/week$(date +%V)/full_$(date -d "-1day" +%Y%m%d)
    else
        INCREMENTAL_BASEDIR=$BACKUP_DIR/week$(date +%V)/incremental_$(date -d "-1day" +%Y%m%d)
    fi
}

[[ -z "$INCREMENTAL" ]] && {
   if [[ $DAYTH -eq $INCRE_START_BACKUP_DAY ]]; then
        INCREMENTAL=$BACKUP_DIR/week$(date +%V)/incremental_$(date +%Y%m%d)
    else
        INCREMENTAL=$BACKUP_DIR/week$(date +%V)/incremental_$(date +%Y%m%d)
    fi
}

[[ -d $INCREMENTAL ]] && {
    log "ERROR" "$INCREMENTAL already exists. Aborting!"
    exit 1
}

if [[ $MYSQL_VERSION -eq 1 ]]; then
    incremental_backup $XTRA_BIN_DIR_FOR51
else
    incremental_backup $XTRA_BIN_DIR
fi

mv $BACKUP_TMP_LOG "$INCREMENTAL"

tail -1 "${INCREMENTAL}"/backup.log|grep -q "completed OK!" &&
    echo "success." || echo "failed."


exit 0
