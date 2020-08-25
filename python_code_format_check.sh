#!/usr/bin/env bash
# python_code_format_check.sh
#
# check your python codes format


CODE_DIR=$1

[[ -z "$CODE_DIR" ]] && {
    echo "Usage: $0 <file|dir>" 1>&2
    exit 1
}

set -x

mypy "$CODE_DIR"
black "$CODE_DIR" --check -l 79
black "$CODE_DIR" --diff -l 79
isort "$CODE_DIR" --recursive --check-only
flake8 "$CODE_DIR"

