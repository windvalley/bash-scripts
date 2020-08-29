#!/bin/bash
# sshtunnel_lb_proxy.sh
#
# 2017/09/07


[[ "$#" -ne 1 ]] && { echo "Usage:$0 <IP_FILE>";exit 1;}

IP_FILE=$1
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$WORK_DIR" || exit 1

[[ -f "$IP_FILE" ]] || { echo "err: $IP_FILE not exist!";exit 1;}
! grep -vE '^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$' \
    "$IP_FILE" || { echo "err: $IP_FILE format wrong!";exit 1;}

user=root
client_ip=172.0.0.0/16
start_idx=10
proxy_ip_num="$(grep -c . "$IP_FILE")"
lb_start_idx=$proxy_ip_num

iptables -F
iptables -Z
iptables -X
iptables -t mangle -F
iptables -t mangle -Z
iptables -t mangle -X
iptables -t mangle -N HUWANG
iptables -t mangle -A PREROUTING -j HUWANG
# security policy
# shellcheck disable=SC2002
iptables -t mangle -A HUWANG -s $client_ip \
    -d "$(cat "$IP_FILE"|xargs|sed 's/ /,/g')" -j DROP

# kill all ssh tunnels before
# shellcheck disable=SC2009
ps axu|grep 'pointopoint' |grep -v 'grep pointopoint'|
    awk '{print $2}'|xargs kill -9 &>/dev/null

# shellcheck disable=SC2095
while read -r proxy_ip;do
    local_id=$start_idx
    peer_id=5
    tun_src_ip=192.168.$start_idx.1
    tun_dst_ip=192.168.$start_idx.2

    grep -q '^#PermitTunnel no' /etc/ssh/sshd_config && {
        sed -i "s/^#PermitTunnel no/PermitTunnel yes/" "$_"
        /etc/init.d/sshd reload &>/dev/null
    }

    iptables -t mangle -A HUWANG -s $client_ip -d $tun_src_ip -j RETURN
    iptables -t mangle -A HUWANG -s $client_ip -d $tun_dst_ip -j RETURN
    iptables -t mangle -A HUWANG -s $client_ip -m statistic --mode nth \
        --every "$lb_start_idx" --packet 0 -j TEE --gateway $tun_dst_ip

    ssh -f -o PermitLocalCommand=yes \
        -o LocalCommand="ifconfig tun$local_id $tun_src_ip pointopoint $tun_dst_ip netmask 255.255.255.0" \
        -o ServerAliveInterval=60 \
        -o StrictHostKeyChecking=no \
        -w "$local_id:$peer_id $user@$proxy_ip" "
nic=\$(ifconfig |grep -B 1 $proxy_ip|head -1|awk '{print \$1}')
ifconfig tun$peer_id $tun_dst_ip pointopoint $tun_src_ip netmask 255.255.255.0
grep -q '^#PermitTunnel no' /etc/ssh/sshd_config && {
    sed -i \"s/^#PermitTunnel no/PermitTunnel yes/\" \$_
    /etc/init.d/sshd reload
}
{
iptables -t nat -D POSTROUTING -o \$nic -j MASQUERADE
iptables -t nat -A POSTROUTING -o \$nic -j MASQUERADE
iptables -D FORWARD -i \$nic -o tun$peer_id -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i \$nic -o tun$peer_id -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -D FORWARD -i tun$peer_id -o \$nic -j ACCEPT
iptables -A FORWARD -i tun$peer_id -o \$nic -j ACCEPT
route add -net $client_ip dev tun$peer_id
service iptables save
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.netfilter.nf_conntrack_max=1655360
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=1200
} &>/dev/null
"
    ((start_idx++))
    ((lb_start_idx--))

done <"$IP_FILE"

{
    /etc/init.d/iptables save
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sysctl -w net.netfilter.nf_conntrack_max=1655360
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=1200
} &>/dev/null

# summarize
# shellcheck disable=SC2009
sshtunnel_success_num=$(ps axu|grep 'pointopoint' |grep -vc 'grep pointopoint')
sshtunnel_failed_num=$((proxy_ip_num-sshtunnel_success_num))
echo "Completed! Ssh tunnel creat success($sshtunnel_success_num), failed($sshtunnel_failed_num)"


exit 0
