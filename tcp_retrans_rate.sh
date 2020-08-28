#!/bin/bash
# tcp_retrans_rate.sh



read -r s_s s_re < <(netstat -s -t |
    grep -E 'segments send out|segments retransmited' | awk '{print $1}' | xargs)

[[ ! -f segments_stats ]] && echo 0 0 > .segments_stats

read -r s_s_last s_re_last < .segments_stats

echo "$s_s $s_re" > .segments_stats

awk 'BEGIN{printf("%.4f",('"$s_re"'-'"$s_re_last"')/('"$s_s"'-'"$s_s_last"')*100)}'


exit 0
