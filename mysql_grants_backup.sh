#!/bin/bash
# mysql_grants_backup.sh


MYSQL_BIN="/usr/local/bin/mysql -uroot -pyourpassword"

{
$MYSQL_BIN -BN -e 'show tables' mysql 2>/dev/null | grep -v Logging |
    while read -r tab; do
        $MYSQL_BIN -BN -e "select user,host from $tab" mysql | grep -v Logging
    done | sort | uniq |
        while read -r user host;do
            $MYSQL_BIN -BN -e "show grants for '$user'@'$host'" |
                grep -v Logging
        done
} 2>/dev/null|sed 's/$/;/' > grants.sql


exit 0
