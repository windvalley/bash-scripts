#!/bin/bash
# mysql_src_install.sh
# for MySQL 5.1.x 5.5.x 5.6.x source code install on CentOS 5.x 6.x
#
# 2015/11/27
#
# -- General Information -- #
# data: $BASE_DIR/var
# my.cnf: $BASE_DIR/etc
# log: $BASE_DIR/log
# tmp: $BASE_DIR/tmp
# service: $BASE_DIR/bin/mysql.server
# client: $BASE_DIR/bin/mysql
# ------------------------- #


MYSQL_SRC_TGZ="/usr/local/src/mysql-5.6.27.tar.gz"
#MYSQL_SRC_TGZ="/usr/local/src/mysql-5.5.46.tar.gz"
#MYSQL_SRC_TGZ="/usr/local/src/mysql-5.1.72.tar.gz"
BASE_DIR="/usr/local/mysql"
PORT="3306"
ROOT_PASSWORD="abcd1234"
MYSQL_MARK=
INNODB_BUFFER_POOL_SIZE="30G"

VERSION_NUM=$(echo ${MYSQL_SRC_TGZ##*/} | grep -Eo '[0-9]+' | xargs |
    awk '{if($NF>=10)print $1""$2""$3;else print $1""$2"0"$3}')
SECOND_VERSION_NUM=$(echo ${MYSQL_SRC_TGZ##*/} | grep -Eo '[0-9]+' |
    xargs | awk '{print $2}')
THIRD_VERSION_NUM=$(echo ${MYSQL_SRC_TGZ##*/} | grep -Eo '[0-9]+' |
    xargs | awk '{print $3}')
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_LOG=$SCRIPT_DIR/mysql${VERSION_NUM}_src_install.log
# shellcheck disable=SC2001
MYSQL_SRC_DIR=$(echo ${MYSQL_SRC_TGZ##*/} | sed 's/.tar.gz//')
EXIT="kill $$"

[[ -z "$PORT" ]] && PORT=$VERSION_NUM
[[ -z "$BASE_DIR" ]] && BASE_DIR=/usr/local/mysql$VERSION_NUM
[[ -z "$ROOT_PASSWORD" ]] && ROOT_PASSWORD="mysql"
[[ -z "$MYSQL_MARK" ]] && MYSQL_MARK=$(hostname)
[[ -z "$INNODB_BUFFER_POOL_SIZE" ]] &&
    INNODB_BUFFER_POOL_SIZE=$(free -m | awk '/Mem/{printf "%dG",$2*0.7/1024}')

DATA_DIR=$BASE_DIR/var
LOG_DIR=$BASE_DIR/log
ETC_DIR=$BASE_DIR/etc
TMP_DIR=$BASE_DIR/tmp


log(){
    time=$(date +%F" "%T)
    echo "$time [$1]: $2" >>"$INSTALL_LOG" 2>&1
}

pipelog(){
    while read -r line;do
        time=$(date +%F" "%T)
        # shellcheck disable=SC2001
        echo "$line" | sed "s/^/$time [$1]: /" >>"$INSTALL_LOG" 2>&1
    done
}

[[ -f "$INSTALL_LOG" ]] && rm -f "$INSTALL_LOG"

[[ -d "$BASE_DIR" ]] && { log "ERROR" "$BASE_DIR already exists.Aborted!";exit 1;}

netstat -nlpt | awk '/^tcp/{print $4}' | awk -F: '{print $NF}' | grep -qw "$PORT" && {
    log "ERROR" "PORT $PORT already in listen.Aborted!";exit 1;}

[[ -f $MYSQL_SRC_TGZ ]] || { log "ERROR" "$MYSQL_SRC_TGZ not exist.Aborted!";exit 1;}

echo $MYSQL_SRC_TGZ|grep -q '\.tar\.gz$' || {
    log "ERROR" "mysql src packet must be Compressed TAR Archive \".tar.gz\". Aborted!"
    exit 1
}

trap "log 'ALERT' 'ctrl+c.Aborted!'
    rm -rf $BASE_DIR $MYSQL_SRC_DIR
    exit 2" 2

log "NOTE" "begin install mysql$VERSION_NUM on $BASE_DIR."

cd ${MYSQL_SRC_TGZ%/*} || exit 1
[[ -d "$MYSQL_SRC_DIR" ]] && rm -rf "$MYSQL_SRC_DIR"
tar zxf $MYSQL_SRC_TGZ || {
    log "ERROR" "mysql source code packet not valid,maybe damaged.Aborted!"
    [[ -d "$MYSQL_SRC_DIR" ]] && rm -rf "$MYSQL_SRC_DIR"
    exit 1
}

log "NOTE" "yum install gcc-c++ gcc make cmake ncurses-devel."
(
exec 2>&1
if yum install -y gcc-c++ gcc make cmake ncurses-devel; then
    log "NOTE" "gcc-c++ gcc make cmake ncurses-devel are installed."
else
    log "ERROR" "gcc-c++ gcc make cmake ncurses-devel installed error.Aborted!"
    exit 1
fi
) | pipelog "yum install"

if grep -q '^mysql:' /etc/passwd; then
    log "WARNING" "user mysql already exists."
else
    groupadd mysql
    useradd -g mysql mysql
    log "NOTE" "user mysql is created."
fi

cd "$MYSQL_SRC_DIR" || exit 1
if [[ "$SECOND_VERSION_NUM" -eq 1 ]]; then
    log "NOTE" "begin configure."
    (
    exec 2>&1
    ./configure  --prefix="$BASE_DIR" --with-unix-socket-path="$TMP_DIR"/mysql.sock \
        --with-plugins=partition,csv,archive,federated,innobase,innodb_plugin,myisam,heap \
        --with-charset=utf8\
        --without-docs \
        --without-man \
        --with-client-ldflags=-static 'CFLAGS=-g -O3' 'CXXFLAGS=-g -O3' \
        --with-extra-charsets=gbk,utf8,ascii,big5,latin1,binary \
        --enable-assembler \
        --enable-local-infile \
        --enable-profiling  \
        --enable-thread-safe-client  &&
            log "NOTE" "configure success." || {
                log "ERROR" "configure error.Aborted!";$EXIT;}
    ) | pipelog "Configure"
else
    log "NOTE" "begin cmake."
    (
    exec 2>&1
    cmake . \
        -DCMAKE_INSTALL_PREFIX="$BASE_DIR"  \
        -DINSTALL_MYSQLDATADIR="$DATA_DIR"  \
        -DMYSQL_DATADIR="$DATA_DIR" \
        -DSYSCONFDIR="$ETC_DIR"    \
        -DWITH_INNOBASE_STORAGE_ENGINE=1  \
        -DDEFAULT_CHARSET=utf8   \
        -DDEFAULT_COLLATION=utf8_general_ci  \
        -DMYSQL_TCP_PORT="$PORT"  \
        -DMYSQL_UNIX_ADDR="$TMP_DIR"/mysql.sock  \
        -DWITH_EXTRA_CHARSETS=all &&
           log "NOTE" "cmake success." ||
               { log "ERROR" "cmake error.Aborted!";$EXIT;}
    ) | pipelog "Cmake"
fi

log "NOTE" "begin make."
(
exec 2>&1
make -j $(grep -c processor /proc/cpuinfo) &&
    log "NOTE" "make success." || { log "ERROR" "make error.Aborted!";$EXIT;}
) | pipelog "make"

log "NOTE" "begin make install."
(
exec 2>&1
make install &&
    log "NOTE" "make install success." || {
        log "ERROR" "make install error.Aborted!";$EXIT;}
) | pipelog "make install"

mkdir -p "$DATA_DIR" "$TMP_DIR" "$LOG_DIR" "$ETC_DIR" &&
    log "NOTE" "create dirs \"$DATA_DIR $TMP_DIR $LOG_DIR $ETC_DIR\"."
chown -R mysql "$DATA_DIR" "$TMP_DIR" "$LOG_DIR" "$ETC_DIR"

log "NOTE" "create $ETC_DIR/my.cnf."
cat >"$ETC_DIR"/my.cnf <<EOF
[client]
port			= $PORT
socket			= $TMP_DIR/mysql.sock

[mysqld]
port			= $PORT
BASE_DIR         	= $BASE_DIR
datadir         	= $DATA_DIR
socket			= $TMP_DIR/mysql.sock
pid-file        	= $DATA_DIR/mysql.pid
tmpdir          	= $TMP_DIR

default-time-zone       = system
character-set-server    = utf8

# default: 0;
old_passwords           = 0

# default: 0
skip-name-resolve

# default: 0
skip-symbolic-links

# default: 0
skip-external-locking

##********** connect **********##

# (<= 5.6.5) default: 50;
# (>= 5.6.6) default: -1(autosized), formula:50+(max_connections/5),capped to a limit of 900;
back_log                 = 50

# default: 151, Max Vaulue: 100000;
max_connections          = 1000

# (<= 5.6.5) default: 10;
# (>= 5.6.6) default: 100;
max_connect_errors       = 10000

# (<= 5.6.7) default: 0;
# (>= 5.6.8) default: 5000, with possible adjustment;
#open_files_limit         = 10240

connect-timeout          = 10
wait-timeout             = 800
interactive-timeout      = 800
net_read_timeout         = 30
net_write_timeout        = 60
net_retry_count          = 10

# thread exclusive; default: 16K, Max Value: 1M;
net_buffer_length        = 16K

# (<= 5.6.5) default: 1M, Max Value: 1G;
# (>= 5.6.6) default: 4M, Max Value: 1G;
# the packet message buffer is initialized to net_buffer_length bytes, but can grow up to max_allowed_packet bytes when needed.
max_allowed_packet       = 64M

##********** cache **********##
$( [ $SECOND_VERSION_NUM -eq 1 -a $THIRD_VERSION_NUM -lt 3 ] && echo "
# (<5.1.3) default:64;
# the number of open tables for all threads;
table_cache    		 = 64
" || echo "
# (>= 5.1.3) default: 64;
# (<= 5.6.7) default: 400;
# (>= 5.6.8) default: 2000;
# the number of open tables for all threads;
table_open_cache    	 = 2048
")

# thread exclusive; default: 192K(32bit), 256K(64bit);
thread_stack             = 256K

# (<= 5.6.7) default: 0;
# (>= 5.6.8) default: -1(autosized);
# how many threads the server should cache for reuse;
thread_cache_size        = 100

# (<= 5.6.7) default: 1;
# (>= 5.6.8) default: 0;
# if cache results in or retrieve results from the query cache;
query_cache_type 	 = 0

# (<= 5.6.7) default: 0;
# (>= 5.6.8) default: 1M;
# The amount of memory allocated for caching query results;
query_cache_size         = 0

# default: 1M;
# do not cache results that are larger than this number of bytes;
query_cache_limit        = 2M

# default: 4K, Min:512;
# the minimum size (in bytes) for blocks allocated by the query cache;
query_cache_min_res_unit = 2K

# default: 16M;
# thread exclusive; the maximum size of internal in-memory temporary tables;
tmp_table_size           = 512M

# default: 16M
max_heap_table_size      = 512M

##********** binlog **********##

log-bin                  	= mysql-bin
log-bin-index            	= mysql-bin.index

max_binlog_size          	= 1G
expire_logs_days         	= 7

# dafault: 0;
# for consistency in a replication setup that uses InnoDB with transactions,set sync_binlog=1;
sync_binlog                     = 1

# thread exclusive; default: 32K, Min Value: 4K;
# (>=5.5.9) for the transaction cache only;
binlog_cache_size               = 1M
$(
[[ $SECOND_VERSION_NUM -eq 5 && $THIRD_VERSION_NUM -ge 9 ]] || [[ $SECOND_VERSION_NUM -ge 6 ]] &&
    echo "
# (>=5.5.9) default: 32K, Min Value: 4K;
# for the statement cache only;
binlog_stmt_cache_size          = 1M
")

# default: 2^64-1, Min Value: 4K;
# (<=5.5.8) a change in max_binlog_cache_size took immediate effect;
# (>=5.5.9) a change in max_binlog_cache_size takes effect only for new sessions that started after the value is changed;
# (>=5.5.9) for the transaction cache only;
max_binlog_cache_size           = 4G
$(
[[ $SECOND_VERSION_NUM -eq 5 && $THIRD_VERSION_NUM -ge 9 ]] || [[ $SECOND_VERSION_NUM -ge 6 ]] &&
    echo "
# (>=5.5.9) default: 16EB, Min Value: 4K;
# for the statement cache only;
max_binlog_stmt_cache_size      = 4G
")
$(
[[ $SECOND_VERSION_NUM -eq 1 && $THIRD_VERSION_NUM -ge 5 ]] || [[ $SECOND_VERSION_NUM -ge 5 ]] &&
    echo "
# Introduced: 5.1.5;
# (>= 5.1.29) default: STATEMENT; values: ROW,STATEMENT,MIXED;
binlog_format                   = STATEMENT
")

##********** replication **********##

# must be unique; range from 1 to 2^32 − 1
server-id 			= $RANDOM$RANDOM

# not to start the slave threads when the slave server starts;
skip-slave-start

relay-log      		 	= relay-log
relay_log_index          	= relay-log.index

# default: 0; Max Value: 1G;
# if max_relay_log_size is 0, the server uses max_binlog_size for both the binary log and the relay log;
max_relay_log_size       	= 1G

# default: 1;
# enable automatic purging of relay logs as soon as they are no longer needed;
relay-log-purge 		= 1

# used for slave SQL thread replicates a LOAD DATA INFILE statement;
slave-load-tmpdir   		= $TMP_DIR

# default: 0;
# slave server log the updates which are received from master server to its own binary log;
# used for A->B->C,and B need this option;
log-slave-updates		= 1

replicate-wild-ignore-table     = mysql.%
replicate-wild-ignore-table     = test.%

# default: OFF; values: OFF,[list of error codes],all;
#slave_skip_errors		= all

# default: 3600;
# seconds to wait for more data from the master before the slave considers the connection broken;
slave-net-timeout        	= 60

##********** logs **********##

# default: 0;
general_log              	= 1
general_log_file         	= $LOG_DIR/mysql.log

# default: 0;
slow_query_log           	= 1
long-query-time          	= 1
slow_query_log_file      	= $LOG_DIR/slow.log

# default: 0;
#log-queries-not-using-indexes  = 1
# default: 0;
#log-slow-slave-statements	= 1

# default: FILE; values: FILE,TABLE,NONE;
# for general and slow query log;
log-output               	= FILE

# default: 1, Min Value: 0, Max Value: 2^64-1
# aborted connections and access-denied errors for new connection attempts are logged if the value is greater than 1;
log-warnings             	= 1
log-error       	 	= $LOG_DIR/mysql.err

##********** for myisam mainly **********##

# for myisam; default: 8M;
key_buffer_size                 = 300M

# thread exclusive; is not specific to any storage engine and applies in a general manner for optimization;
# default: 2047K (<= 5.6.3), 256K (>= 5.6.4)
sort_buffer_size                = 2M

# thread exclusive; for myisam table does a sequential scan and for others also; default: 128K, Max Value: 2G;
read_buffer_size                = 2M

# thread exclusive; for myisam table following a key-sorting operation and for others also; default: 256K, Max Value: 2G;
read_rnd_buffer_size            = 8M

# thread exclusive; default: 128K (<= 5.6.5), 256K (>= 5.6.6);
join_buffer_size                = 8M

# thread exclusive; for myisam; default: 8M
bulk_insert_buffer_size         = 64M

# for sorting MyISAM indexes: REPAIR TABLE,CREATE INDEX,ALTER TABLE; default: 8M
myisam_sort_buffer_size         = 64M

# for re-creating a MyISAM index: REPAIR TABLE,ALTER TABLE,LOAD DATA INFILE; default: 7EB
myisam_max_sort_file_size       = 10G

# default: 1, Min Vaule: 1;
myisam_repair_threads           = 1
$( [[ $SECOND_VERSION_NUM -eq 1 ]] &&
    echo "
# specifying the option with no argument is the same as specifying \"DEFAULT\";
# default: OFF; values: OFF,DEFAULT,BACKUP,FORCE,QUICK;
# \"DEFAULT\":Recovery without backup, forcing, or quick checking.
myisam-recover" ||
        echo "
# specifying the option with no argument is the same as specifying \"DEFAULT\";
# default: OFF; values: OFF,DEFAULT,BACKUP,FORCE,QUICK;
# \"DEFAULT\":Recovery without backup, forcing, or quick checking.
myisam-recover-options
")

# the maximum permitted result length in bytes for the GROUP_CONCAT() function; default: 1K;
group_concat_max_len            = 64K

##********** innodb **********##

# (>= 5.5.5) default: InnoDB; (<= 5.5.4) default: MyISAM;
default-storage-engine   	= InnoDB

# default: REPEATABLE-READ, values: READ-UNCOMMITTED,READ-COMMITTED,REPEATABLE-READ,SERIALIZABLE;
# System Variable: tx_isolation;
transaction-isolation           = REPEATABLE-READ

# ( 5.1.x,>= 5.5.7,<= 5.6.5 ) default: OFF;
# ( <= 5.5.6,>= 5.6.6 ) default: ON;
innodb_file_per_table		= 1

# default: 8M; deprecated at 5.6.3;
# uses to store data dictionary information and other internal data structures;
innodb_additional_mem_pool_size = 10M

# caches table and index data; default: 128M;
# on a dedicated database server, you might set this to up to 80% of the machine physical memory size;
innodb_buffer_pool_size         = $INNODB_BUFFER_POOL_SIZE

innodb_data_home_dir            = $DATA_DIR

# default: ibdata1:10M:autoextend(<= 5.6.6), ibdata1:12M:autoextend(>= 5.6.7);
innodb_data_file_path           = ibdata1:1G:autoextend
$(
[[ $SECOND_VERSION_NUM -eq 1 ]] &&
    echo "
# default: 4 ; on Unix, increasing the number has no effect; InnoDB always uses the default value;
innodb_file_io_threads          = 4
" || echo "
# (>= 5.1.38 InnoDB Plugin only) default: Antelope; values: Antelope,Barracuda;
# (<= 5.5.6) default: Barracuda;
# (>= 5.5.7) default: Antelope;
innodb_file_format 		= Barracuda

# default: 4; Max Value: 64; if 5.1.38, InnoDB Plugin only;
innodb_read_io_threads          = 8

# default: 4; Max Value: 64; if 5.1.38, InnoDB Plugin only;
innodb_write_io_threads         = 8
$(
[[ $SECOND_VERSION_NUM -eq 5 && $THIRD_VERSION_NUM -ge 4 ]] ||
    [[ $SECOND_VERSION_NUM -eq 6 && $THIRD_VERSION_NUM -le 1 ]] &&
        InnodbPurgeThreadsValue=1  || InnodbPurgeThreadsValue=2
echo "
# (>= 5.5.4, <= 5.6.1) default: 0, Max Value: 1;
# (>= 5.6.2, <= 5.6.4) default: 0, Max Value: 32;
# (>= 5.6.5) default: 1, Min Value:1, Max Value: 32;
# can improve efficiency on systems where DML operations are performed on multiple tables;
innodb_purge_threads            = $InnodbPurgeThreadsValue
")
$(
[[ $SECOND_VERSION_NUM -eq 5 && $THIRD_VERSION_NUM -ge 4 ]] ||
    [[ $SECOND_VERSION_NUM -ge 6 ]] &&
        echo "
# (>=5.5.4,<= 5.6.5) default: 1, Max Value: 64;
# (>= 5.6.6) default: 8 (or 1 if innodb_buffer_pool_size < 1GB), Max Value: 64;
innodb_buffer_pool_instances    = 16
")

# if 5.1.38, InnoDB Plugin only;
# (<= 5.5.3) default: inserts; values: inserts,none;
# (>= 5.5.4) default: all; values: none,inserts,deletes,changes,purges,all;
innodb_change_buffering         = all

# if 5.1.38, InnoDB Plugin only;
# default: 200, Min Value: 100, Max Value: 2^64-1;
# this parameter should be set to approximately the number of I/O operations that the system can perform per second;
# ideally, keep this setting as low as practical, but not so low that these background activities fall behind;
innodb_io_capacity              = 2000

# if 5.1.41, InnoDB Plugin only;
# (<=5.6.5) default: 0, Max Value: 2^32-1;
# (>= 5.6.6) default: 1000(ms), Max Value: 2^32-1;
# non-zero values protect against the buffer pool being filled up by data that is referenced only for a brief period, such as during a full table scan
innodb_old_blocks_time          = 1000
")
$(
[[ $SECOND_VERSION_NUM -eq 1 && $THIRD_VERSION_NUM -ge 17 ]] ||
    [[ $SECOND_VERSION_NUM -ge 5 ]] &&
        echo "
# Introduced: 5.1.17;
# (>= 5.1.17,<= 5.6.5) default: ON;
# (>= 5.6.6) default: OFF;
innodb_stats_on_metadata        = 0
")

# 5.1 Default: 8, Max Value: 1000;
# 5.5 5.6 Default: 0, Max Value: 1000;
# 0 is interpreted as infinite concurrency (no concurrency checking);
# in some cases, the optimal innodb_thread_concurrency setting can be smaller than the number of vCPUs.
innodb_thread_concurrency       = 16

# default: 1; values: 0,1,2;
# 1 is required for full ACID compliance;
innodb_flush_log_at_trx_commit  = 1

# Default: 8M, Max Value: 4G;
# if you have transactions that update, insert, or delete many rows,then make the log buffer larger;
innodb_log_buffer_size          = 16M

# (<= 5.6.2) 	       default: 5M, Max Value: 4GB/innodb_log_files_in_group;
# (>= 5.6.3, <= 5.6.7) default: 5M, Max Value: 512GB/innodb_log_files_in_group;
# (>= 5.6.8)           default: 48M, Max Value: 512GB/innodb_log_files_in_group;
# Sensible values range from 1MB to 1/innodb_log_files_in_group of the size of the buffer pool;
innodb_log_file_size            = 100M

# default: 2, Min Value: 2, Max Value: 100;
# InnoDB writes to the files in a circular fashion; The default (and recommended) value is 2;
innodb_log_files_in_group       = 2

innodb_log_group_home_dir       = $DATA_DIR

# default: 75, Min Value: 0, Max Value: 99;
innodb_max_dirty_pages_pct      = 90
$(
[[ $SECOND_VERSION_NUM -ge 5 ]] && echo "
# if 5.1.38, InnoDB Plugin only;
# default: ON;
innodb_adaptive_flushing      	= 1
")

# default: 50, Min Value: 1;
# the timeout in seconds an InnoDB transaction waits for a row lock before giving up;
# when a lock wait timeout occurs, the current statement is rolled back (not the entire transaction);
innodb_lock_wait_timeout        = 50

# default: OFF;
# if ON, a transaction timeout causes InnoDB to abort and roll back the entire transaction;
innodb_rollback_on_timeout      = 0

# default: NULL;
# (<= 5.6.6) values: fsync,littlesync,nosync,O_DSYNC,O_DIRECT;
# (>= 5.6.7) values: fsync,O_DSYNC,littlesync,nosync,O_DIRECT,O_DIRECT_NO_FSYNC;
# if NULL, the fsync option is used by default;
# fsync: InnoDB uses the fsync() system call to flush both the data and log files. fsync is the default setting;
# O_DIRECT: InnoDB uses O_DIRECT to open the data files, and uses fsync() to flush both the data and log files;
innodb_flush_method             = O_DIRECT

[mysqldump]
quick
max_allowed_packet              = 64M

[mysql]
no-auto-rehash
prompt				= "(\\\u@$MYSQL_MARK \\\w \\\R:\\\m:\\\s)[\\\d](\\\c)> "
pager				= "less -i -n -S"
tee 				= "$LOG_DIR/query.log"
default-character-set           = utf8
connect-timeout                 = 3

[myisamchk]
$([[ $SECOND_VERSION_NUM -eq 1 ]] && echo "
key_buffer 			= 256M
" || echo "
key_buffer_size 		= 256M
")
sort_buffer_size 		= 256M
read_buffer 			= 2M
write_buffer 			= 2M

[mysqlhotcopy]
interactive-timeout

EOF

(
exec 2>&1
[[ $SECOND_VERSION_NUM -eq 1 ]] && MYSQL_INSTALL_DB="$BASE_DIR/bin/mysql_install_db" ||
    MYSQL_INSTALL_DB="$BASE_DIR/scripts/mysql_install_db"

log "NOTE" "$MYSQL_INSTALL_DB --user=mysql --defaults-file=$ETC_DIR/my.cnf --basedir=$BASE_DIR"

"$MYSQL_INSTALL_DB" --user=mysql --defaults-file="$ETC_DIR"/my.cnf --basedir="$BASE_DIR" &&
    log "NOTE" "mysql_install_db success." || {
        log "ERROR" "mysql_install_db error.Aborted!";$EXIT;}
) | pipelog "make install db"

[[ -f /etc/my.cnf ]] &&
    { rm -f /etc/my.cnf;log "NOTE" "/etc/my.cnf removed."; } ||
        log "NOTE" "/etc/my.cnf not exists."
[[ -f /etc/mysql/my.cnf ]] && {
    rm -f /etc/mysql/my.cnf;log "NOTE" "/etc/mysql/my.cnf removed."; } ||
        log "NOTE" "/etc/mysql/my.cnf not exists."
[[ -f ~/.my.cnf ]] && {
    rm -f ~/.my.cnf;log "NOTE" "~/.my.cnf removed."; } ||
        log "NOTE" "~/.my.cnf not exists."
[[ -f $BASE_DIR/my.cnf ]] && {
    rm -f $BASE_DIR/my.cnf;log "NOTE" "$BASE_DIR/my.cnf removed."; } ||
        log "NOTE" "$BASE_DIR/my.cnf not exists."

(
exec 2>&1
[[ "$SECOND_VERSION_NUM" -eq 1 ]] &&
    MYSQL_SERVER="$BASE_DIR/share/mysql/mysql.server" ||
        MYSQL_SERVER="$BASE_DIR/support-files/mysql.server"
cp "$MYSQL_SERVER" "$BASE_DIR"/bin/ && log "NOTE" "mysql.server at $BASE_DIR/bin/mysql.server."
"$BASE_DIR"/bin/mysql.server start && log "NOTE" "mysqld start success." || {
    log "ERROR" "mysqld start failed.Aborted!";$EXIT;}
) | pipelog "mysql.server"

"$BASE_DIR"/bin/mysqladmin password "$ROOT_PASSWORD" 2>/dev/null &&
    log "NOTE" "set root password success." || {
        log "ERROR" "set root password failed.Aborted!";exit 1;}

log "NOTE" "drop users that user is null or password is null."
DROP_NULL_USER_SQL=$("$BASE_DIR"/bin/mysql -uroot -p"$ROOT_PASSWORD" -NBe "
    select user,host from mysql.user where (user is null or user='') or (password is null or password='')" 2>/dev/null|
        grep -v 'Logging to file'|awk '{if(NF==2)print "drop user \x27"$1"\047@\047"$2"\047;";
            else print "drop user \x27\047@\047"$1"\047;"}')

(
exec 2>&1
echo "$DROP_NULL_USER_SQL" | "$BASE_DIR"/bin/mysql -uroot -p"$ROOT_PASSWORD"
echo "$DROP_NULL_USER_SQL"
) | pipelog "NOTE"

log "NOTE" "MySQL$VERSION_NUM installed success. End."


exit 0
