#!/bin/bash
# mysql_status_check.sh
#
# check mysql servers status
# 2013/12/01


# shellcheck disable=SC1091
source /etc/bashrc

MYSQL_CONN="mysql -uroot -pxxx"


compute(){
    formula="$1"
    awk 'BEGIN{printf("%.2f",'"$formula"')}' 2>/dev/null &&
         echo "$value" || echo NULL
}

unset UPTIME
eval "$($MYSQL_CONN -e "show global status" | awk '{print $1"=\x27"$2"\047"}')"
[[ X = X"$UPTIME" ]] || exit 1

qps=$(compute "$Questions/$UPTIME")
tps=$(compute "($Com_commit+$Com_rollback)/$UPTIME")
reads=$(compute "$Com_select+$Qcache_hits")
writes=$(compute "$Com_insert+$Com_update+$Com_delete+$Com_replace")
rwratio=$(compute "$reads/$writes*100")%
key_buffer_read_hits=$(compute "(1-$Key_reads/$Key_read_requests)*100")%
key_buffer_write_hits=$(compute "(1-$Key_writes/$Key_write_requests)*100")%
query_cache_hits=$(compute "$Qcache_hits/($Qcache_hits+$Qcache_inserts)*100")%
innodb_buffer_read_hits=$(compute "(1-$Innodb_buffer_pool_reads/$Innodb_buffer_pool_read_requests)*100")%
thread_cache_hits=$(compute "(1-$Threads_created/$Connections)*100")%
slow_queries_per_second=$(compute "$Slow_queries/$UPTIME*60")
select_full_join_per_second=$(compute "$Select_full_join/$UPTIME*60")
select_full_join_in_all_select=$(compute "($Select_full_join/$Com_select)*100")%
myisam_lock_contention=$(compute "($Table_locks_waited/$Table_locks_immediate)*100")%
temp_tables_to_disk_ratio=$(compute "($Created_tmp_disk_tables/$Created_tmp_tables)*100")%

# print formated MySQL status report
title="******************** MySQL $host General Status ***********************"
width=${#title}

echo "$title"

export IFS=':'
while read -r name value;do
    printf "%36s :\t%10s\n" "$name" "$value"
done <<EOF
Query per second(QPS):$qps
Transactions per second(TPS):$tps
Reads:$reads
Writes:$writes
Read/Writes Ratio:$rwratio
MyISAM Key buffer read hits(>99%):$key_buffer_read_hits
MyISAM Key buffer write hits:$key_buffer_write_hits
Query cache hits:$query_cache_hits
InnoDB buffer read hits(>95%):$innodb_buffer_read_hits
Thread cache hits(>90%):$thread_cache_hits
Slow queries per second:$slow_queries_per_second
Select full join per second:$select_full_join_per_second
Select full join in all select:$select_full_join_in_all_select
MyiSAM lock contention(<1%):$myisam_lock_contention
Temp tables to disk ratio:$temp_tables_to_disk_ratio
EOF

unset IFS

for _ in $(seq "$width");do
    echo -n "*"
done

echo


exit 0
