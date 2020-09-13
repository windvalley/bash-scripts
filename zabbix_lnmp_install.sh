#!/bin/bash
# zabbix_lnmp_install.sh
# 2015/12/13


SRC_DIR=/usr/local/src/zabbix_src_install
MYSQL_SRCTGZ=$SRC_DIR/mysql-5.6.28.tar.gz
NGINX_SRCTGZ=$SRC_DIR/nginx-1.9.9.tar.gz
PHP_SRCTGZ=$SRC_DIR/php-5.6.16.tar.gz
ZABBIX_SRCTGZ=$SRC_DIR/zabbix-2.4.7.tar.gz
# shellcheck disable=SC2001
MYSQL_SRC_DIR=$(echo ${MYSQL_SRCTGZ##*/}|sed 's/.tar.gz//')
# shellcheck disable=SC2001
NGINX_SRC_DIR=$(echo ${NGINX_SRCTGZ##*/}|sed 's/.tar.gz//')
# shellcheck disable=SC2001
PHP_SRC_DIR=$(echo ${PHP_SRCTGZ##*/}|sed 's/.tar.gz//')
# shellcheck disable=SC2001
ZABBIX_SRC_DIR=$(echo ${ZABBIX_SRCTGZ##*/}|sed 's/.tar.gz//')

ZABBIX_BASEDIR=/home/zabbix
ZABBIX_DIR=$ZABBIX_BASEDIR/zabbix_server
NGINX_DIR=$ZABBIX_BASEDIR/nginx
PHP_DIR=$ZABBIX_BASEDIR/php
MYSQL_DIR=$ZABBIX_BASEDIR/mysql

MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD=mysql
ZABBIX_MYSQL_USER=zabbix
ZABBIX_MYSQL_HOST=localhost
ZABBIX_MYSQL_PASS=zabbix


yum -y groupinstall "Development Tools"
yum install -y gcc-c++ gcc make cmake ncurses-devel libxml2 libxml2-devel \
    openssl openssl-devel libcurl-devel libpng-devel libjpeg-devel \
    freetype-devel pcre pcre-devel net-snmp net-snmp-devel

groupadd zabbix
useradd -g zabbix -m zabbix
[ ! -d $ZABBIX_BASEDIR ] && mkdir -p $ZABBIX_BASEDIR
chmod 755 $ZABBIX_BASEDIR
chown zabbix. $ZABBIX_BASEDIR

/etc/init.d/iptables stop
grep -q  '^SELINUX=enforcing' /etc/selinux/config && {
        sed -i '/^SELINUX=enforcing/s/^.*$/SELINUX=disabled/' /etc/selinux/config
        /usr/sbin/setenforce 0
}

#### install mysql
useradd mysql -s /sbin/nologin
(
cd $SRC_DIR || exit 1

tar zxf $MYSQL_SRCTGZ
cd "$MYSQL_SRC_DIR" || exit 1

cmake . \
    -DCMAKE_INSTALL_PREFIX=$MYSQL_DIR  \
    -DINSTALL_MYSQLDATADIR="$MYSQL_DIR/var"  \
    -DMYSQL_DATADIR=$MYSQL_DIR/var \
    -DSYSCONFDIR=$MYSQL_DIR/etc    \
    -DWITH_INNOBASE_STORAGE_ENGINE=1  \
    -DDEFAULT_CHARSET=utf8mb4   \
    -DDEFAULT_COLLATION=utf8mb4_general_ci  \
    -DMYSQL_TCP_PORT=$MYSQL_PORT  \
    -DMYSQL_UNIX_ADDR=$MYSQL_DIR/tmp/mysql.sock  \
    -DWITH_EXTRA_CHARSETS=all
make -j "$(grep -c processor /proc/cpuinfo)"
make install

cd "$MYSQL_DIR" || exit 1
mkdir log tmp etc var
chown -R mysql log tmp var
rm -f /etc/my.cnf   /etc/mysql/my.cnf   ~/.my.cnf
cp $SRC_DIR/my.cnf etc/my.cnf
sed -i "s#/usr/local/mysql#$MYSQL_DIR#" etc/my.cnf
scripts/mysql_install_db --user=mysql --defaults-file=$MYSQL_DIR/etc/my.cnf \
    --basedir=$MYSQL_DIR --datadir=$MYSQL_DIR/var
cp support-files/mysql.server ./bin/
./bin/mysql.server start
)

echo "$MYSQL_DIR/lib" > /etc/ld.so.conf.d/mysql-x86_64.conf
ldconfig

$MYSQL_DIR/bin/mysqladmin password "$MYSQL_ROOT_PASSWORD"
DropNullUserSql=$($MYSQL_DIR/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -NBe "
    select user,host from mysql.user where (user is null or user='') or (password is null or password='')" 2>/dev/null|
    grep -v 'Logging to file'|
    awk '{if(NF==2)print "drop user \x27"$1"\047@\047"$2"\047;";
    else print "drop user \x27\047@\047"$1"\047;"}')
echo "$DropNullUserSql" | $MYSQL_DIR/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD"

$MYSQL_DIR/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
    -e "grant all privileges on *.* to '$ZABBIX_MYSQL_USER'@'$ZABBIX_MYSQL_HOST' identified by '$ZABBIX_MYSQL_PASS'"


# install php
(
cd "$SRC_DIR" || exit 1
tar zxf $PHP_SRCTGZ
cd "$PHP_SRC_DIR" || exit 1
./configure  \
--prefix=$PHP_DIR \
--with-config-file-path=$PHP_DIR/etc \
--enable-fpm \
--with-fpm-user=php-fpm \
--with-fpm-group=php-fpm \
--with-mysql=$MYSQL_DIR \
--with-pdo-mysql=$MYSQL_DIR \
--with-mysqli=$MYSQL_DIR/bin/mysql_config \
--with-gd \
--with-png-dir \
--with-jpeg-dir \
--with-libxml-dir \
--with-zlib-dir \
--with-freetype-dir \
--with-gettext \
--with-iconv-dir \
--with-pear \
--with-curl \
--with-openssl \
--disable-ipv6 \
--enable-bcmath \
--enable-mbstring \
--enable-sockets

make -j "$(grep -c processor /proc/cpuinfo)"  && make install

cp php.ini-production $PHP_DIR/etc/php.ini
sed -i '/max_execution_time/s/^.*/max_execution_time = 600 /
        /date.timezone/s/^.*$/date.timezone = Asia\/Shanghai/
        /post_max_size/s/^.*$/post_max_size = 32M/
        /memory_limit/s/^.*/memory_limit = 128M/
        /mbstring.func_overload/s/^.*$/mbstring.func_overload = 2/
        /max_input_time/s/^.*/max_input_time = 600/
        /mbstring.func_overload/s/^.*/mbstring.func_overload = 0/
        /;always_populate_raw_post_data = -1/s/^.*/always_populate_raw_post_data = -1/
        /upload_max_filesize/s/^.*$/upload_max_filesize = 16M /' $PHP_DIR/etc/php.ini

\cp sapi/fpm/init.d.php-fpm $PHP_DIR/bin/php-fpm.server
chmod +x $PHP_DIR/bin/php-fpm.server
cd "$PHP_DIR"/etc || exit 1
\cp php-fpm.conf.default  php-fpm.conf
useradd php-fpm -s /sbin/nologin
$PHP_DIR/bin/php-fpm.server start
)

### nginx install
(
cd "$SRC_DIR" || exit 1
tar zxf $NGINX_SRCTGZ
cd "$NGINX_SRC_DIR" || exit 1
./configure \
--prefix=$NGINX_DIR \
--with-http_realip_module \
--with-http_sub_module \
--with-http_gzip_static_module \
--with-http_stub_status_module  \
--with-pcre

make -j "$(grep -c processor /proc/cpuinfo)"
make install
)

cat >$NGINX_DIR/conf/nginx.conf<<EOF
user nobody nobody;
worker_processes 2;
error_log logs/nginx_error.log crit;
pid logs/nginx.pid;
worker_rlimit_nofile 51200;

events
{
    use epoll;
    worker_connections 6000;
}

http
{
    include mime.types;
    default_type application/octet-stream;
    server_names_hash_bucket_size 3526;
    server_names_hash_max_size 4096;
    log_format combined_realip '\$remote_addr \$http_x_forwarded_for [\$time_local]'
    '\$host "\$request_uri" \$status'
    '"\$http_referer" "\$http_user_agent"';
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 30;
    client_header_timeout 3m;
    client_body_timeout 3m;
    send_timeout 3m;
    connection_pool_size 256;
    client_header_buffer_size 1k;
    large_client_header_buffers 8 4k;
    request_pool_size 4k;
    output_buffers 4 32k;
    postpone_output 1460;
    client_max_body_size 10m;
    client_body_buffer_size 256k;
    client_body_temp_path $NGINX_DIR/client_body_temp;
    proxy_temp_path $NGINX_DIR/proxy_temp;
    fastcgi_temp_path $NGINX_DIR/fastcgi_temp;
    fastcgi_intercept_errors on;
    tcp_nodelay on;
    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 8k;
    gzip_comp_level 5;
    gzip_http_version 1.1;
    gzip_types text/plain application/x-javascript text/css text/htm application/xml;

server
{
    listen 80;
    server_name localhost;
    index index.html index.htm index.php;
    root $NGINX_DIR/html;

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $NGINX_DIR/html\$fastcgi_script_name;
    }
}
}
EOF

$NGINX_DIR/sbin/nginx

cat >$NGINX_DIR/html/test.php<<EOF
<?php
    #echo "test";
    phpinfo();
?>
EOF

### zabbix install
! grep -q zabbix /etc/services &&
        cat >>/etc/services <<EOF
zabbix-agent    10050/tcp                       # Zabbix Agent
zabbix-agent    10050/udp                      # Zabbix Agent
zabbix-trapper  10051/tcp                       # Zabbix Trapper
zabbix-trapper  10051/udp                      # Zabbix Trapper
EOF

(
cd "$SRC_DIR" || exit 1
tar zxf $ZABBIX_SRCTGZ
cd "$ZABBIX_SRC_DIR" || exit 1
./configure --prefix=$ZABBIX_DIR \
        --enable-server --enable-agent \
        --with-mysql=$MYSQL_DIR/bin/mysql_config \
        --with-net-snmp \
        --with-libcurl
make -j "$(grep -c processor /proc/cpuinfo)"
make install

\cp -r frontends/php $NGINX_DIR/html/zabbix
chmod 777 $NGINX_DIR/html/zabbix/conf

$MYSQL_DIR/bin/mysql -uroot -p$MYSQL_ROOT_PASSWORD -e "create database zabbix"
$MYSQL_DIR/bin/mysql -uroot -p$MYSQL_ROOT_PASSWORD zabbix <database/mysql/schema.sql
$MYSQL_DIR/bin/mysql -uroot -p$MYSQL_ROOT_PASSWORD zabbix <database/mysql/images.sql
$MYSQL_DIR/bin/mysql -uroot -p$MYSQL_ROOT_PASSWORD zabbix <database/mysql/data.sql

\cp misc/init.d/tru64/zabbix_server $ZABBIX_DIR/bin/zabbix_server_ctrl
\cp misc/init.d/tru64/zabbix_agentd $ZABBIX_DIR/bin/zabbix_agentd_ctrl

sed -i "s!DAEMON=/usr/local/sbin/zabbix_server!$ZABBIX_DIR/sbin/zabbix_server!" \
    $ZABBIX_DIR/bin/zabbix_server_ctrl
sed -i "s!DAEMON=/usr/local/sbin/zabbix_agentd!$ZABBIX_DIR/sbin/zabbix_agentd!" \
    $ZABBIX_DIR/bin/zabbix_agentd_ctrl
chmod +x $ZABBIX_DIR/bin/{zabbix_server_ctrl,zabbix_agentd_ctrl}

sed -i "/# DBHost=localhost/s/.*/DBHost=$ZABBIX_MYSQL_HOST/;
	/# DBPort=3306/s/.*/DBPort=$MYSQL_PORT/;
	/^DBUser=root/s/.*/DBUser=$ZABBIX_MYSQL_USER/;
	/# DBPassword=/s/.*/DBPassword=$ZABBIX_MYSQL_PASS/" $ZABBIX_DIR/etc/zabbix_server.conf

$ZABBIX_DIR/bin/zabbix_server_ctrl start
$ZABBIX_DIR/bin/zabbix_agentd_ctrl start
)

cat >>/etc/rc.d/rc.local<<EOF
$MYSQL_DIR/bin/mysql.server start
$PHP_DIR/bin/php-fpm.server start
$NGINX_DIR/sbin/nginx
$ZABBIX_DIR/bin/zabbix_server_ctrl start
$ZABBIX_DIR/bin/zabbix_agentd_ctrl start
EOF


exit 0
