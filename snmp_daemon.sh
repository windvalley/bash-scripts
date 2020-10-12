#!/usr/bin/env bash
# snmp_daemon.sh
# Execute snmp_record.sh every 300 seconds


WORK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export INTER_SECONDS=300


until [[ $(date +%M|cut -c 2) =~ 0|5 && $(date +%S) -lt 10 ]] ;do :;done

while :;do
  # shellcheck disable=SC2155
  export _TIME=$(date +%Y%m%d%H%M)
  "$WORK_DIR"/snmp_record.sh &
  sleep $INTER_SECONDS
done


exit 0
