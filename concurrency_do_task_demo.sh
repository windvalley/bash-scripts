#!/usr/bin/env bash
# concurrency_do_task_demo.sh
#
# Usage:
#    handle_threads 100 "obj1 obj2 obj3 ..." func


handle_threads(){
    local threads_num=$1;shift
    local object_list=$1;shift
    local command="$*"

    [[ -z "$command" ]] && {
        # shellcheck disable=SC2128
        echo "Usage: $FUNCNAME threads_num object_list command"
        return 1
    }

    tmp_fifofile="/tmp/$$.fifo"
    mkfifo $tmp_fifofile
    exec 6<> $tmp_fifofile
    for ((i=0; i<threads_num; i++));do
        echo
    done >&6

    for object in $object_list;do
        read -r -u6
        {
            $command "$object"
            echo >&6
        } &
    done

    wait
    exec 6>&-
    rm -f $tmp_fifofile
}

handle_threads_v2() {
    local threads_num=$1;shift
    local object_list=$1;shift
    local command="$*"

    [[ -z "$command" ]] && {
        # shellcheck disable=SC2128
        echo "Usage: $FUNCNAME threads_num object_list command"
        return 1
    }

    for object in $object_list;do
        {
            $command "$object"
        } &

        while :; do
            # shellcheck disable=SC2009
            sum=$(ps axu|grep -v grep|grep -c "${command%% *}")
            # shellcheck disable=SC2015
            [[ $sum -ge $threads_num ]] && continue || break
        done
    done
}
