#!/bin/bash
# mysql_innobackupex_restore.sh
# for mysql5.1,5.5,5.6
# 2015/12/3
#
#********** restore **********
#1. ./mysql_innobackupex_restore.sh --apply-log --redo-only fulldir
#   ./mysql_innobackupex_restore.sh --apply-log --redo-only fulldir --incremental-dir=incremental1
#   ./mysql_innobackupex_restore.sh --apply-log fulldir --incremental-dir=incremental2(last incremental not add "--redo-only".)
#   ./mysql_innobackupex_restore.sh --apply-log fulldir
#
#2. bin/mysql.server stop && mv var/ var.bak
#   ./mysql_innobackupex_restore.sh --copy-back fulldir
#   cp -r var.bak/mysql var/; cp -r var.bak/performance_schema var/(copy back databases which not backuped.)
#   chown -R mysql var/
#
#3. bin/mysqlbinlog --start-position=10 --stop-position=100 var.bak/mysql-bin.000007 >007.sql
#   bin/mysql.server start
#   bin/mysql -uroot -ppassword <007.sql
#
#4. check
#*****************************


XTRA_BIN_DIR=/usr/local/src/percona-xtrabackup-2.3.2-Linux-x86_64/bin
XTRA_BIN_DIR_FOR51=/usr/local/src/percona-xtrabackup-2.0.8/bin
USE_MEMORY=1G
ARGS="$*"
# shellcheck disable=SC2046
WORK_DIR=$(cd $(dirname "$0") && pwd)
RESTORE_LOG=$WORK_DIR/restore.log

MYSQL_BASEDIR=/usr/local/mysql5627
MYSQL_ETC_FILE=$MYSQL_BASEDIR/etc/my.cnf
MYSQL_USER=root
MYSQL_PASSWORD=mysql
MYSQL_SOCKET=$MYSQL_BASEDIR/tmp/mysql.sock
MYSQL_VERSION=$($MYSQL_BASEDIR/bin/mysql -V|
    grep -Eo 'Distrib [0-9.]+'|awk -F. '{print $2}')

log(){
    time=$(date +%F" "%T)
    echo "$time [$1]: $2" >>"$RESTORE_LOG" 2>&1
}

pipelog(){
    while read -r line;do
        time=$(date +%F" "%T)
        # shellcheck disable=SC2001
        echo "$line"|sed "s/^/$time [$1]: /" >>"$RESTORE_LOG" 2>&1
    done
}

restore(){
    bin_dir=$1
    export PATH="$PATH:${bin_dir}:$MYSQL_BASEDIR/bin"
    log "innobackupex" "$ARGS"

    (
    exec 2>&1
    "$bin_dir"/innobackupex \
        --defaults-file="$MYSQL_ETC_FILE" \
        --user="$MYSQL_USER" \
        --password="$MYSQL_PASSWORD" \
        --socket="$MYSQL_SOCKET" \
	    --use_memory="$USE_MEMORY" \
	    "$ARGS"
    ) | pipelog "innobackupex restore"
}

if [[ "$MYSQL_VERSION" -eq 1 ]]; then
    restore $XTRA_BIN_DIR_FOR51
else
    restore $XTRA_BIN_DIR
fi

tail -1 "$RESTORE_LOG" | grep -q "completed OK!" &&
    echo "success." || echo "failed."


exit 0
