#!/usr/bin/env bash
# python_code_format.sh
#
# format your python codes


CODE_DIR=$1

[[ -z "$CODE_DIR" ]] && {
    echo "Usage: $0 <file|dir>" 1>&2
    exit 1
}


set -e
set -x


# Sort imports one per line, so autoflake can remove unused imports
isort "$CODE_DIR" --recursive  --force-single-line-imports --apply

autoflake "$CODE_DIR" --remove-all-unused-imports --recursive \
    --remove-unused-variables --in-place --exclude=__init__.py

black "$CODE_DIR" -l 79

isort "$CODE_DIR" --recursive --apply

