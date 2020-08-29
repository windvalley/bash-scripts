#!/bin/bash
# lnmp_src_install.sh
# 2016/4/18


SRCDIR=/usr/local/src/lnmp_install
NGINX_SRCTGZ=$SRCDIR/nginx-1.9.9.tar.gz
PHP_SRCTGZ=$SRCDIR/php-5.6.16.tar.gz
# shellcheck disable=SC2001
NGINX_SRCDIR=$(echo ${NGINX_SRCTGZ##*/}|sed 's/.tar.gz//')
# shellcheck disable=SC2001
PHP_SRCDIR=$(echo ${PHP_SRCTGZ##*/}|sed 's/.tar.gz//')

NGINX_DIR=/usr/local/nginx
PHP_DIR=/usr/local/php
MYSQL_DIR=/usr/local/mysql


yum -y groupinstall "Development Tools"
yum install -y gcc-c++ gcc make cmake ncurses-devel pcre pcre-devel
yum install -y libxml2 libxml2-devel openssl openssl-devel libcurl-devel \
    libpng-devel libjpeg-devel freetype-devel
yum install -y pcre pcre-devel
yum install -y net-snmp net-snmp-devel

/etc/init.d/iptables stop
grep -q  '^SELINUX=enforcing' /etc/selinux/config && {
    sed -i '/^SELINUX=enforcing/s/^.*$/SELINUX=disabled/' /etc/selinux/config
    /usr/sbin/setenforce 0
}

# install php
(
cd $SRCDIR || exit 1
tar zxf $PHP_SRCTGZ
cd "$PHP_SRCDIR" || exit 1
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
cd $PHP_DIR/etc || exit 1
\cp php-fpm.conf.default  php-fpm.conf
useradd php-fpm -s /sbin/nologin
$PHP_DIR/bin/php-fpm.server start
)

# nginx install
(
cd $SRCDIR || exit 1
tar zxf $NGINX_SRCTGZ
cd "$NGINX_SRCDIR" || exit 1
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

cat >>/etc/rc.d/rc.local<<EOF
$MYSQL_DIR/bin/mysql.server start
$PHP_DIR/bin/php-fpm.server start
$NGINX_DIR/sbin/nginx
EOF


exit 0
