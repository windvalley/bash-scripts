#!/usr/bin/env bash
# snmp_record.sh
# 2018/07/27

WORK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IDC_INFO_DIR="idc_info"
IDC_SNMP_DATA_DIR="raw_snmp_data"
LOG_DIR="log"
MONTH=$(date +%Y%m)
TIME_NOW=$(date +%Y%m%d%H%M)
_TIME=${_TIME:-$TIME_NOW}
INTER_SECONDS=${INTER_SECONDS:-300}
THREADS_NUM=20
MAIL_TO="foo@xxx.com,bar@xxx.com"

cd "$WORK_DIR" || exit 1
mkdir -p $IDC_SNMP_DATA_DIR $LOG_DIR

log() {
    local subject=$1
    local content=$2
    local log_file=$3
    # shellcheck disable=SC2155
    local log_time=$(date +%F" "%T)

    # shellcheck disable=SC2128
    [[ "$#" -ne 3 ]] && {
        echo "Usage: $FUNCNAME <subject> <content> <log file>"
        exit 1
    }
    echo "$log_time [$subject]: $content" >>"$log_file" 2>&1
}

get_snmp() {
    local out_or_in=$1
    local ip=$2
    local community=$3
    local index=$4
    local timeout=$5
    snmpwalk -v 2c "$ip" -c "$community" ifHC"${out_or_in}"Octets."$index" -t "$timeout" 2>/dev/null
}

handle_threads() {
    local THREADS_NUM=$1
    shift
    local object_list=$1
    shift
    local command="$*"

    # shellcheck disable=SC2128
    [[ -z "$command" ]] && {
        echo "Usage: $FUNCNAME THREADS_NUM object_list command"
        return 1
    }

    tmp_fifofile="/tmp/$$.fifo"
    mkfifo $tmp_fifofile
    exec 6<>$tmp_fifofile
    for ((i = 0; i < THREADS_NUM; i++)); do echo; done >&6

    for object in $object_list; do
        read -r -u6
        {
            # shellcheck disable=SC2086
            $command $object
            echo >&6
        } &
    done

    wait
    exec 6>&-
    rm -f $tmp_fifofile
}

snmp_record() {
    local idc_txt=$1
    # shellcheck disable=SC2155
    local idc_name=$(echo "$idc_txt" | awk -F/ '{print $NF}' | sed 's/.info//')

    mkdir -p $IDC_SNMP_DATA_DIR/"$idc_name"/"$MONTH"
    cd $IDC_SNMP_DATA_DIR/"$idc_name" || exit 1

    while IFS=$',' read -r ip if community index; do
        if_=$(echo "$if" | sed 's/\//_/g')
        read -r _ out_sum_old in_sum_old < <(cat ."${ip}"_"$if"_ 2>/dev/null)
        out_sum_raw=$(get_snmp Out "$ip" "$community" "$index" 0.3 ||
            get_snmp Out "$ip" "$community" "$index" 0.4)
        in_sum_raw=$(get_snmp In "$ip" "$community" "$index" 0.3 ||
            get_snmp In "$ip" "$community" "$index" 0.4)
        out_sum=$(echo "$out_sum_raw" | awk '{print $NF}')
        in_sum=$(echo "$in_sum_raw" | awk '{print $NF}')

        # check valid of the snmp data
        [[ ! "$out_sum" =~ [0-9]+ || "$out_sum" -eq 0 || "$in_sum" -eq 0 ]] && {
            log "$idc_name snmp error" "${ip}_$if $community $index:: out:$out_sum in:$in_sum" \
                "$WORK_DIR"/$LOG_DIR/error_"$MONTH".log
            # shellcheck disable=SC2188
            >."${ip}":"${if_}":"${community}":"${index}".timeout
            continue
        }

        out=$(((out_sum - out_sum_old) * 8 / INTER_SECONDS))
        in=$(((in_sum - in_sum_old) * 8 / INTER_SECONDS))

        # out and in is not greater than 10G
        [[ "$out" -gt 10000000000 || "$out" -le 0 ]] && {
            out=$(tail -3 "$MONTH"/"${ip}"_"$if_" 2>/dev/null |
                awk '{sum+=$2}END{printf"%d",sum/3*0.987}')
            out=${out:-0}
        }
        [[ "$in" -gt 10000000000 || "$in" -le 0 ]] && {
            in=$(tail -3 "$MONTH"/"${ip}"_"$if_" 2>/dev/null |
                awk '{sum+=$3}END{printf"%d",sum/3*0.988}')
            in=${in:-0}
        }

        echo "$_TIME $out $in" >>"$MONTH"/"${ip}"_"${if_}"
        echo "$_TIME $out_sum $in_sum" >."${ip}"_"${if_}"
    done <"$WORK_DIR"/"$idc_txt"

    # shellcheck disable=SC2185
    [[ $(find -type f -name ".*timeout") ]] || {
        sum=$(grep -H "$_TIME" "$MONTH"/* | grep -v "${idc_name}.txt" |
            awk -F: '{print $NF}' | awk '{sum1+=$2;sum2+=$3}END{print $1,sum1,sum2}')
        echo "$sum" >>"$MONTH"/"${idc_name}".txt
    }
}

# main
handle_threads "$THREADS_NUM" "$IDC_INFO_DIR/*.info" snmp_record

# shellcheck disable=SC2009
until ! ps axu | grep -v grep | grep -q snmpwalk; do :; done

# for timeout or err instance to retry
for idc in "$IDC_SNMP_DATA_DIR"/*; do
    idc_name=$(echo "$idc" | awk -F/ '{print $2}')
    cd "$WORK_DIR"/"$idc" || exit 1

    timeout_file=$(find . -type f -name "*timeout*")

    for timeout_info in $timeout_file; do
        ip=$(echo "$timeout_info" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        if_=$(echo "$timeout_info" | awk -F: '{print $2}')
        community=$(echo "$timeout_info" | awk -F: '{print $3}')
        index=$(echo "$timeout_info" | awk -F: '{print $4}' | awk -F. '{print $1}')

        read -r _ out_sum_old in_sum_old < <(cat ."${ip}"_"${if_}" 2>/dev/null)
        out_sum_raw=$(get_snmp Out "$ip" "$community" "$index" 0.3 ||
            get_snmp Out "$ip" "$community" "$index" 0.4 ||
            get_snmp Out "$ip" "$community" "$index" 0.5 ||
            echo "$idc_name $ip $community ifHCOutOctets.$index" |
            mail -s "[SNMP TIMEOUT]$idc_name" $MAIL_TO)
        in_sum_raw=$(get_snmp In "$ip" "$community" "$index" 0.3 ||
            get_snmp In "$ip" "$community" "$index" 0.4 ||
            get_snmp In "$ip" "$community" "$index" 0.5)
        out_sum=$(echo "$out_sum_raw" | awk '{print $NF}')
        in_sum=$(echo "$in_sum_raw" | awk '{print $NF}')

        # check valid of the snmp data
        [[ ! "$out_sum" =~ [0-9]+ || "$out_sum" -eq 0 || "$in_sum" -eq 0 ]] && {
            log "$idc_name snmp error" "${ip}_$if_ $community $index:: out:$out_sum in:$in_sum" \
                "$WORK_DIR"/$LOG_DIR/error_"$MONTH".log
            read -r out in < <(tail -3 "$MONTH"/"${ip}"_"$if_" 2>/dev/null |
                awk '{sum1+=$2;sum2+=$3}END{printf"%d %d",sum1/3*0.998,sum2/3*0.999}')
            out=${out:-0}
            in=${in:-0}
            echo "$_TIME $out $in" >>"$MONTH"/"${ip}"_"${if_}"
            echo "$_TIME $out_sum $in_sum" >."${ip}"_"$if_"
            rm -f "$timeout_info"
            continue
        }

        out=$(((out_sum - out_sum_old) * 8 / INTER_SECONDS))
        in=$(((in_sum - in_sum_old) * 8 / INTER_SECONDS))

        # out and in is not greater than 10G
        [[ "$out" -gt 10000000000 || "$out" -le 0 ]] && {
            out=$(tail -3 "$MONTH"/"${ip}"_"$if_" 2>/dev/null |
                awk '{sum+=$2}END{printf"%d",sum/3*0.987}')
            out=${out:-0}
        }
        [[ "$in" -gt 10000000000 || "$in" -le 0 ]] && {
            in=$(tail -3 "$MONTH"/"${ip}"_"$if_" 2>/dev/null |
                awk '{sum+=$3}END{printf"%d",sum/3*0.988}')
            in=${in:-0}
        }
        echo "$_TIME $out $in" >>"$MONTH"/"${ip}"_"${if_}"
        echo "$_TIME $out_sum $in_sum" >."${ip}"_"${if_}"
        rm -f "$timeout_info"
    done

    [[ -n "$timeout_file" ]] && {
        sum=$(grep -H "$_TIME" "$MONTH"/* | grep -v "${idc_name}.txt" |
            awk -F: '{print $2}' | awk '{sum1+=$2;sum2+=$3}END{print $1,sum1,sum2}')
        echo "$sum" >>"$MONTH"/"${idc_name}".txt
    }
done

exit 0
