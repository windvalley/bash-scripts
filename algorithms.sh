#!/usr/bin/env bash
# algorithms.sh
# some algorithms implemented by bash


yanghui_triangle(){
    local max_line=$1
    # all the first column is 1
    a[0]=1
    # i is line
    for ((i=0; i<max_line; i++));do
        # j is column
        for ((j=i; j>0; j--));do
            ((a[j]+=a[j-1]))
        done
        # print the i line
        echo "${a[@]}"
        sleep 0.1
    done
}

yanghui_triangle 20


fibonacci_sequence(){
    local num=$1
    local fib=(1 1)

    for ((n=2;n<=num;n++));do
        fib[n]=$((fib[n-1] + fib[n-2]))
    done

    echo "${fib[@]}"
    # NOTE: bash version must gather than 4.0
    echo "scale=8;${fib[-2]}/${fib[-1]}" | bc
}

fibonacci_sequence 30

