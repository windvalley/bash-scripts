#!/bin/bash
# iptables_load_balancer.sh
#
# Implement load balancer by iptables (rr), and should setup by root.
# 2017/7/21


set -u

# usage
[[ "$#" -ne 1 ]] && { echo "Usage:./$0 <IPLIST_file>";exit 1;}


PORT=1080
IPLIST=$1
PROTOCAL=tcp
BASEDIR=/usr/local/iptables-lb
LOGDIR=$BASEDIR/log
LOG_SAVEDAYS=30

# enable supports forward
sed -i 's/^net.ipv4.ip_forward.*$/net.ipv4.ip_forward  = 1/' /etc/sysctl.conf
sysctl -q -p

# set iptables policy
iptables -t nat -F
iptables -F

[[ -f /etc/sysconfig/iptables.lbbak ]] || cp /etc/sysconfig/iptables{,.lbbak}

linenu=1
while read -r ip;do
    echo "iptables -t nat -A PREROUTING -p $PROTOCAL --dport $PORT \
        -m statistic --mode nth --every $linenu --packet 0 \
        -j DNAT --to-destination $ip"
    ((linenu++))
done < "$IPLIST" | sort -k15 -nr|bash

iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -p $PROTOCAL --dport $PORT -j LOG \
    --log-prefix 'IPTABLES_FORWARD_LOG:' --log-level debug
iptables-save >/etc/sysconfig/iptables

/etc/init.d/iptables restart

# set iptables log
mkdir -p $LOGDIR
grep -q '^kern\.\*' /etc/rsyslog.conf &&
    sed -i "s#^kern\.\*.*#kern.* $LOGDIR/access.log#" /etc/rsyslog.conf ||
        echo "kern.* $LOGDIR/access.log" >>/etc/rsyslog.conf
/etc/init.d/rsyslog restart

cat >$LOGDIR/logrotate.sh<<EOF
#!/bin/bash
# log rotate
/bin/mv $LOGDIR/access.log{,.\$(/bin/date +%Y%m%d_%H%M%S)}
/etc/init.d/rsyslog reload
/bin/find $LOGDIR -type f -mtime $LOG_SAVEDAYS -exec rm -f {} \;
exit 0
EOF

chmod u+x $LOGDIR/logrotate.sh
grep -q "$LOGDIR/logrotate.sh" /var/spool/cron/root ||
    echo "0 * * * * $LOGDIR/logrotate.sh" >>/var/spool/cron/root

# ip pool servers live detect
cat >$BASEDIR/ip_pool_probe.sh <<EOF
#!/bin/bash
# ip pool live detect
rootdir=\$(cd \$(dirname \$0) && pwd)
cd \$rootdir
>fail_ip.txt >probe.log
while sleep 3;do
while read ip;do
    if nc -4vzw 2 \$ip $PORT &>/dev/null;then
        grep -q \$ip fail_ip.txt && {
            eval \$(grep "PREROUTING.*--to-destination" /etc/sysconfig/iptables |
                head -1|sed -r "s/[ /t]*$//;s/^/iptables -t nat /;s/ [0-9.]+$/ \$ip/")
            sed -i "/\$ip/d" fail_ip.txt
            echo "[\$(date +%F" "%T)]: \$ip:$PORT recover" >>probe.log
        }
    else
        grep -q \$ip fail_ip.txt && continue
        eval \$(grep "\--to-destination \$ip" /etc/sysconfig/iptables |
            sed 's/^-A/iptables -t nat -D/')
        echo \$ip >>fail_ip.txt
        echo "[\$(date +%F" "%T)]: \$ip:$PORT not connect" >>probe.log
    fi
done < <(grep "PREROUTING.*--to-destination" /etc/sysconfig/iptables | awk '{print \$NF}')
done
exit 0
EOF

chmod u+x $BASEDIR/ip_pool_probe.sh
killall ip_pool_probe.sh &>/dev/null
($BASEDIR/ip_pool_probe.sh &)

[[ -f $BASEDIR/$(basename "$0") ]] || cp ./"$0" "$IPLIST" "$BASEDIR"

echo "SUCCESS: IPTABLES-LB SETUP COMPLETE!"


exit 0
