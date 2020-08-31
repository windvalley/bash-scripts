#!/bin/bash
# script_locker_demo.sh
#
# Add a lock to your script to avoid errors caused by repeated execution.


WORK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_NAME=$(basename "$0")
LOG_FILE="$WORK_DIR/${SCRIPT_NAME}.log"
LOCK_FILE="/var/run/${SCRIPT_NAME}.pid"


trap "unlock
log 'killed' 'process is killed.'
exit 1
echo" INT TERM


log(){
    local subject=$1
    shift
    local content=$*
    echo "$(date +%F' '%T) [$subject]: $content" >>"$LOG_FILE" 2>&1
}

pipelog(){
    local subject=$1
    while read -r content_line;do
        # shellcheck disable=SC2001
        echo "$content_line"|
            sed "s/^/$(date +%F" "%T) [$subject]: /" >>"$LOG_FILE" 2>&1
    done
}

# create a lock file
lock(){
    if [[ -f "$LOCK_FILE" ]];then
        pid=$(cat "$LOCK_FILE")
        msg="Existing lock $LOCK_FILE: another copy is running as pid $pid"
        log "locked" "$msg"
        echo "$msg"
        exit 1
    fi

    echo $$ >"$LOCK_FILE"
}

# delete the lock file
unlock(){
    rm -f "$LOCK_FILE"
}


some_logic(){
    exec 2>&1
    cd "$WORK_DIR" || exit 1

    echo "here is your project logic"
}


main(){
    lock

    some_logic | pipelog "your project brief description"

    unlock
}


main


exit 0
