#!/usr/bin/env bash
# print_256colors.sh
#

column=18

echo -e "background colors:\n"

for i in {0..255}; do
    printf '\e[48;5;%dm%3d ' "$i" "$i"
    # shellcheck disable=SC2004
    (((i + 3) % $column)) || printf '\e[0m\n'
done

printf '\e[0m\n\n\n'

echo -e "foreground colors:\n"

for i in {0..255}; do
    printf '\e[38;5;%dm%3d ' "$i" "$i"
    # shellcheck disable=SC2004
    (((i + 3) % $column)) || printf '\e[0m\n'
done | sed 's/%//'

exit 0
