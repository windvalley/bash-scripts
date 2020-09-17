#!/bin/bash
# progress_bar_demo.sh


COMPANY_IPLIST="
10.0.0.0/8
192.168.0.0/16
"
DYNAMIC_PASSWORD=$1
PROXY_HOST=vpn


usage(){
    grep -qE '^[[:digit:]]{6}$' <<< "$DYNAMIC_PASSWORD" || {
        echo "Usage: $0 <six digits>"
        exit 1
    }
}


start_macapps(){
    cd /Applications || exit
    open -g "Parallels Desktop.app"
}


progress_bar(){
    _command="$*"
    progress(){
        local interval=1
        while :;do
            echo -e ".\c"
            sleep $interval
        done
    }
    ( # () is for preventing outputs of kill command
        progress &
        progress_pid=$!
        $_command
        kill $progress_pid
    )
}


server_connect_test(){
    echo -n "Connecting the virtual server, please wait"
    until [[ "$ok" = "ok" ]]; do
        ok=$(ssh -o ConnectTimeout=2 $PROXY_HOST "echo ok" 2>/dev/null)
        sleep 0.5
    done
    echo -e "\nConnected."
}


connect_vpn(){
    echo "Connecting the VPN..."
    # shellcheck disable=SC2029
    ssh $PROXY_HOST "sudo ./connect_vpn.sh $DYNAMIC_PASSWORD"
}


delete_routes(){
    for ip in $COMPANY_IPLIST;do
        sudo route delete -net "$ip"
    done
}


add_routes(){
    gateway=$(ssh vpn "/sbin/ifconfig eth1|grep -w inet|awk '{print \$2}'")
    for ip in $COMPANY_IPLIST;do
        sudo route add -net "$ip" "$gateway"
    done
}


main(){
    usage
    start_macapps
    progress_bar server_connect_test
    connect_vpn
    delete_routes &>/dev/null
    add_routes
}


main

