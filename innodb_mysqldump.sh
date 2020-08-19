#!/bin/bash
#
# innodb_mysqldump.sh
# Crontab:
#   8 0 * * *  /bin/bash /yourpath/innodb_mysqldump.sh db1 db2 ...


WORK_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
TIME_FORMAT=$(date +%Y%m%d_%H)
BACKUP_DIR=$WORK_DIR/data/$TIME_FORMAT
LOG_FILE=$BACKUP_DIR/mysqldump.log
SAVE_DAYS=16
DB_USER=root
DB_PASSWORD=123456
DB_NAMES=$*
MYSQLDUMP_BIN=/usr/bin/mysqldump


usage(){
    echo "Usage: $0 db1 db2 ..."
    exit 1
}


log(){
    echo "$(date +%F' '%T) [$1]: $2" >>"$LOG_FILE" 2>&1
}


pipelog(){
    local subject=$1
    while read -r line;do
        echo $line|sed "s/^/$(date +%F" "%T) [$subject]: /" >>$LOG_FILE 2>&1
    done
}


# permanent save backups of the first day of every month.
permanent_save(){
    [[ "$TIME_FORMAT" =~ ^.*01_.*$ ]] && chattr +i "$BACKUP_DIR"/*
}


clean(){
    find "$BACKUP_DIR"/.. -mtime +"$SAVE_DAYS" -type d -0 |
        xargs rm -rf {} >/dev/null 2>&1
}


backup(){
    exec 2>&1

    local user=$1
    local passwd=$2

    [[ ! -d $BACKUP_DIR ]] && mkdir -p "$BACKUP_DIR"

    cd "$BACKUP_DIR" || exit 1

    for db in $DB_NAMES;do
        dump_file=${db}.sql
        $MYSQLDUMP_BIN "$user" "$passwd" --skip-opt --add-drop-table \
            --create-options --extended-insert=false --hex-blob --force \
            --default-character-set=utf8 --master-data=2 --single-transaction \
            --quick --routines --triggers --databases "$db" \
            -r "$dump_file"

        flag=$?
        [[ "$flag" -ne 0 ]] && {
            echo "mysqldump error, status code $flag"
            continue
        }

        if grep -q "Dump completed" "$dump_file";then
            tar zcf "${dump_file}".tgz "$dump_file"
            echo "[${dump_file}.tgz] Backup Success!"
        else
            echo "[${dump_file}.tgz] Backup Failed!"
            exit 1
        fi

        file_size=$(ls -l ${dump_file}.tgz | awk '{print $5}')
        file_md5=$(md5sum ${dump_file}.tgz | awk '{print $1}')

        echo "$file_md5 $file_size" > "${dump_file}".tgz.md5

        rm -f "$dump_file"
    done
}


main(){
    [[ -z "$DB_NAMES" ]] && usage

    if [[ -z "$DB_PASSWORD" ]];then
        backup -u$DB_USER | pipelog "backup"
    else
        backup -u$DB_USER -p$DB_PASSWORD | pipelog "backup"
    fi

    permanent_save
    clean
}


main

