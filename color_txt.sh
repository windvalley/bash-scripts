#!/usr/bin/env bash
# color_txt.sh

color() {
    local role=$1
    shift
    local str="$*"

    case $role in
    success | ok)
        color=[32m
        ;;
    failure | fail)
        color=[31m
        ;;
    warning | warn)
        color=[33m
        ;;
    *)
        color=[39m # default white color
        ;;
    esac

    echo -e "\033$color$str\033[m"
}

# e.g.
echo -n "mysql started "
color success "[OK]"

color ok [OK]

color fail error found

color warn warning

color other hello world
