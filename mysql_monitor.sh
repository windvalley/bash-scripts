#!/usr/bin/env bash
# mysql_monitor.sh
# 2015/8/19


ALARM_GROUP=appops
ALARM_URL="http://alarm.sre.im/alarm"
ERROR_LOG="/var/log/mysqlmonitor.log"
SECONDS_BEHIND_MASTER_THRESHOLD=60
PROCESS_COUNT_THRESHOLD=300
MYSQL_CLIENT="mysql -uxxx -pxxx"
MYSQL_AB=$($MYSQL_CLIENT -e "show slave status" 2>/dev/null |grep -v Logging)


alarm(){
    hostname=$(hostname)
    subject="[MySQL]$hostname $1"
    content="$hostname $2"
    date=$(date +%F_%T)

    echo "$date group_name=$ALARM_GROUP&subject=$subject&content=$content" >> $ERROR_LOG
    curl -d "group_name=$ALARM_GROUP" -d "subject=$subject" \
        -d "content=$content" $ALARM_URL -s >> $ERROR_LOG
}

# mysqld process check
# shellcheck disable=SC2009
mysqld_process_num=$(ps axu|grep -v grep |grep -c mysqld)
[[ "$mysqld_process_num" -lt 2 ]] && {
        subject="MysqldError"
        content="MysqldError : "$mysqld_process_num

        alarm "$subject" "$content"
}

# processlist monitor
process_total=$($MYSQL_CLIENT -e "show processlist" | grep -vc Sleep)
process_total=$(("$process_total"-1))
[[ "$process_total" -gt "$PROCESS_COUNT_THRESHOLD" ]] && {
        subject="MysqlProcesslistNumber"
        content="MysqlProcesslistNumber : $process_total"
        alarm "$subject" "$content"
}

# if master, then exit
[[ -z "$MYSQL_AB" ]] && exit 0

# replication monitor
slave_io_running=$($MYSQL_CLIENT -e "show slave status\G" |
    grep 'Slave_IO_Running:' |awk '{print $NF}')
slave_sql_running=$($MYSQL_CLIENT -e "show slave status\G" |
    grep 'Slave_SQL_Running:' |awk '{print $NF}')

if [[ "$slave_io_running" != "Yes" ]] || [[ "$slave_sql_running" != "Yes" ]]; then
        subject="MysqlReplicationError"
        content="MysqlReplicationError: Slave_IO_Running:$slave_io_running Slave_SQL_Running:$slave_sql_running"
        alarm "$subject" "$content"
fi

# replication delay monitor
seconds_behind_master=$($MYSQL_CLIENT -e "show slave status\G" |
    grep Seconds_Behind_Master | awk '{print $NF}')

[[ "$seconds_behind_master" -gt "$SECONDS_BEHIND_MASTER_THRESHOLD" ]] && {
        subject="MysqlReplicationDelaySeconds"
        content="MysqlReplicationDelaySeconds: $seconds_behind_master"
        alarm "$subject" "$content"
}


exit 0
