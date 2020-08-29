#!/bin/bash
# nic_traffic_mo.sh
# 2015/03/01


ALARM_GROUP="appops"
ALARM_API="http://alarm.sre.im/alarm"
ERRORLOG_FILE="/var/log/ifs_monitor.log"
TMPFILE="/tmp/$RANDOM$RANDOM.$$"
THRESHOLD=96

alarm(){
    hostname=$(hostname)
    subject="[IF_MO]$hostname $1 $2"
    content=$(cat $TMPFILE)
    date=$(date +%F_%T)

    echo "$date group_name=$ALARM_GROUP&subject=$subject&content=$content" >> $ERRORLOG_FILE
    curl -x $ALARM_API -d "group_name=$ALARM_GROUP" -d \
        "subject=$subject" -d "content=$content" $ALARM_API -s >> $ERRORLOG_FILE
}

sar -n DEV 1 1|grep IFACE|tail -1|grep -q B

flag=$?
ifs=$(/sbin/ifconfig |grep HWaddr|awk '{print $1}'|grep -v tun|grep -v :)
for i in $ifs;do
    std=$(ethtool "$i" | grep Speed | grep -Eo '[0-9]+')
    [[ -z "$std" ]] || {
        eval "$i=$std"
        if [[ $flag -eq 0 ]]; then
            traffic=$(sar -n DEV 2 5|grep "$i" |tail -1 |
                awk 'NR==1{printf("%.0f\t%.0f",$5*8/1024,$6*8/1024)}')
        else
            traffic=$(sar -n DEV 2 5 | grep "$i" | tail -1 |
                awk 'NR==1{printf("%.0f\t%.0f",$5*8/1024/1024,$6*8/1024/1024)}')
            echo "$i" "${!i}" "$traffic"
        fi
    }
done >$TMPFILE

while read -r if_ std rx tx;do
        THRESHOLD_=$(awk 'BEGIN{printf("%.0f",'"$std*$THRESHOLD"'/100)}')
        [[ $rx -ge $THRESHOLD_ && $tx -ge $THRESHOLD_ ]] && {
                alarm "$if_|${std}M" "入${rx}Mb|出${tx}Mb      "
                break
        }
done <$TMPFILE

rm -f $TMPFILE


exit 0
