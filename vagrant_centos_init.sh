#!/bin/bash
# vagrant_centos_init.sh
# 2016/05/01

WORK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PRIVATE_DIR=/private
OS_VERSION=$(grep -Eo '[0-9]+' /etc/centos-release | cut -c 1 | head -1)

disable_selinux() {
    sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
    sudo setenforce 0
}

config_ntpdate() {
    local cron_file=/var/spool/cron/vagrant
    sudo yum install -y ntpdate
    sudo timedatectl set-timezone Asia/Shanghai
    sudo /usr/sbin/ntpdate time1.aliyun.com
    if [[ ! -e "$cron_file" ]] || ! sudo grep -q ntpdate $cron_file; then
        sudo bash -c "echo '*/5 * * * * sudo /usr/sbin/ntpdate time1.aliyun.com' >>$cron_file"
    fi
}

config_yum() {
    if diff "${OS_VERSION}"-CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo; then
        return
    fi

    sudo cp /etc/yum.repos.d/CentOS-Base.repo{,.bak}
    sudo cp "${OS_VERSION}"-CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo
    sudo yum makecache
    sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
}

install_tools() {
    local kernel="kernel-devel cpp gcc gcc-c++ libstdc++-devel binutils elfutils-libelf
        elfutils-libelf-devel elfutils-libs libgcc libgomp libstdc++"
    local tools="net-tools curl wget bash-completion lsof zip unzip pcre pcre-devel
        zlib zlib-devel make sysstat bash-completion"
    sudo yum install -y "$kernel" "$tools"
}

install_vim() {
    sudo yum install -y vim
    mkdir -p ~/.vim/.{backup,swp,undo}
    ln -s vimrc ~/.vimrc
}

install_python3() {
    sudo yum install -y python3
    sudo cp pip.conf /etc/
    sudo pip3 install ipython
}

install_openresty() {
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo -y
    sudo yum install -y openresty openresty-resty openresty-opm openresty-doc
}

install_go() {
    sudo yum install -y golang
    mkdir -p ~/go/bin
    grep -q GOPATH ~/.bash_profile ||
        cat >>~/.bash_profile <<-'EOF'
# Go
GOPATH=$HOME/go
GOBIN=$GOPATH/bin
PATH="$GOBIN:$PATH"
GOPROXY=https://goproxy.io
export GOPATH GOBIN PATH GOPROXY
EOF
}

install_docker() {
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    sudo yum-config-manager --add-repo \
        https://mirrors.ustc.edu.cn/docker-ce/linux/centos/docker-ce.repo
    sudo sed -i 's/download.docker.com/mirrors.ustc.edu.cn\/docker-ce/g' \
        /etc/yum.repos.d/docker-ce.repo
    sudo yum makecache fast
    sudo yum install docker-ce -y

    sudo systemctl enable docker
    sudo systemctl start docker

    sudo bash -c 'cat >/etc/docker/daemon.json <<EOF
{
    "registry-mirrors": ["https://hub-mirror.c.163.com"]
}
EOF'

    sudo systemctl restart docker

    sudo groupadd docker
    sudo usermod -aG docker "$USER"

    sudo sh -c "curl -L https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose"
    sudo chmod +x /usr/local/bin/docker-compose
}

main() {
    cd "$WORK_DIR" || exit 1
    disable_selinux
    config_ntpdate
    config_yum
    install_tools
    install_vim
    install_python3
    install_openresty
    install_go
    install_docker
    echo "finished!"
}

main &>${PRIVATE_DIR}/"${0}".log
