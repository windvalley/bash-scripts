#!/usr/bin/env bash
# random.sh
#
# Generate random string, you can custom string length, and default 10 length.
# Random string generated by this scripts as follows:
#   0594254895
#   XVWwvGaqNBjCRwLoWhHf
#   CfomcurFXyOmFX9Hfm4N3422P5c7rj


# shellcheck disable=SC2120
digits_rand(){
    local num=$1
    local idx=0
    local str=""

    [ -z "$num" ] && num=10

    for i in {0..9};do
        arr[idx]=${i}
        ((idx++))
    done
    for i in $(seq 1 $num);do
        str="$str${arr[$RANDOM%$idx]}"
    done

    echo "$str"
}

letters_rand(){
    local num=$1
    local idx=0
    local str=""

    [ -z "$num" ] && num=10

    for i in {a..z} {A..Z};do
        arr[idx]=${i}
        ((idx++))
    done
    for i in $(seq 1 $num);do
        str="$str${arr[$RANDOM%$idx]}"
    done

    echo "$str"
}

alphanumeric_rand(){
    local num=$1
    local idx=0
    local str=""

    [ -z "$num" ] && num=10

    for i in {a..z} {A..Z} {0..9};do
        arr[idx]=${i}
        ((idx++))
    done
    for i in $(seq 1 $num);do
        str="$str${arr[$RANDOM%$idx]}"
    done

    echo "$str"
}

digits_rand
letters_rand 20
alphanumeric_rand 30
