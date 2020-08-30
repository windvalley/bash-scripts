#!/bin/bash
# zabbix_agent_install.sh
# 2015/12/18


ZABBIX_SRCTGZ=/usr/local/src/zabbix-2.4.7.tar.gz
# shellcheck disable=SC2001
ZABBIX_SRCDIR=$(echo ${ZABBIX_SRCTGZ##*/}|sed 's/.tar.gz//')
ZABBIX_AGENT_DIR=/home/zabbix/zabbix_agent
ZABBIX_SERVER=10.211.55.10
#local_ip=$(ifconfig eth0|grep 'inet addr:'|awk '{print $2}'|awk -F: '{print $2}' )
HOSTNAME=$(awk -F'=' '/^hostname/{print $2}' /etc/sysconfig/network)

grep -q  '^SELINUX=enforcing' /etc/selinux/config && {
    sed -i '/^SELINUX=enforcing/s/^.*$/SELINUX=disabled/' /etc/selinux/config
    /usr/sbin/setenforce 0
}

groupadd zabbix
useradd -g zabbix -m zabbix

! grep -q zabbix /etc/services &&
        cat >>/etc/services <<EOF
zabbix-agent    10050/tcp                      # Zabbix Agent
zabbix-agent    10050/udp                      # Zabbix Agent
EOF

cd ${ZABBIX_SRCTGZ%/*} || exit 1
tar zxf $ZABBIX_SRCTGZ

cd "$ZABBIX_SRCDIR" || exit 1
./configure --prefix=$ZABBIX_AGENT_DIR --enable-agent
make -j "$(grep -c processor /proc/cpuinfo)"
make install

\cp misc/init.d/tru64/zabbix_agentd $ZABBIX_AGENT_DIR/bin/zabbix_agentd_ctrl
sed -i "s#DAEMON=/usr/local/sbin/zabbix_agentd#$ZABBIX_AGENT_DIR/sbin/zabbix_agentd#" \
    $ZABBIX_AGENT_DIR/bin/zabbix_agentd_ctrl
chmod +x $ZABBIX_AGENT_DIR/bin/zabbix_agentd_ctrl

grep -q zabbix_agentd_ctrl /etc/rc.d/rc.local ||
	cat >>/etc/rc.d/rc.local<<EOF
$ZABBIX_AGENT_DIR/bin/zabbix_agentd_ctrl start
EOF

sed -i '/^Server=/s/^.*$/Server='"$ZABBIX_SERVER"'/' \
    $ZABBIX_AGENT_DIR/etc/{zabbix_agentd.conf,zabbix_agent.conf}
sed -i '/^ServerActive=/s/^.*$/ServerActive='"$ZABBIX_SERVER"'/' \
    $ZABBIX_AGENT_DIR/etc/zabbix_agentd.conf
sed -i '/^hostname/s/.*/hostname='"$HOSTNAME"'/' \
    $ZABBIX_AGENT_DIR/etc/zabbix_agentd.conf

$ZABBIX_AGENT_DIR/bin/zabbix_agentd_ctrl start


exit 0
