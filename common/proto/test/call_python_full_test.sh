#!/bin/bash
set -e -u

# @file
# @brief Tests the `call_python_client` CLI and `call_python` test together.

cc_bin_flags=
while [[ $# -gt 2 ]]; do
    case ${1} in
        --no_plotting)
            cc_bin_flags='--gtest_filter=-TestCallPython.Plot*'
            shift;;
        *)
            echo "Bad argument: ${1}" >&2
            exit 1;;
    esac
done

cc_bin=${1}
py_client_cli=${2}
# TODO(eric.cousineau): Use `tempfile` once we can choose which file C++
# uses.
filename=$(mktemp)
done_file=${filename}_done

py-error() {
    echo "ERROR: Python client did not exit successfully."
    exit 1
}

pause() {
    # General busy-spinning.
    sleep 0.5
}

should-fail() {
    echo "This should have failed!"
    exit 2
}

sub-tests() {
    # Execute sub-cases.
    func=${1}
    # Sub-case 1: Nominal
    # @note This setup assumes other things succeeded.
    echo -e "\n\n\n[ ${func}: nominal ]"
    do-setup 0 0
    ${func}
    # Sub-case 2: With Error
    echo -e "\n\n\n[ ${func}: with_error ]"
    do-setup 1 0
    ${func}
    # Sub-case 3: With Error + Stop on Error
    echo -e "\n\n\n[ ${func}: with_error + stop_on_error ]"
    do-setup 1 1
    ${func}
}

py-check() {
    # Check the status of the Python executable (either `wait ...` or the
    # executable itself).
    if [[ ${py_fail} -eq 0 ]]; then
        # Should succeed.
        "$@" || py-error
    else
        # Should fail.
        # TODO(eric.cousineau): File / find bug in Bash for this; this behaves
        # differently depending on how this is placed in a function.
        { "$@" && should-fail; } || :
    fi
}

do-setup() {
    py_fail=${1}
    py_stop_on_error=${2}

    cc_flags="--file=${filename} --done_file=${done_file}"
    if [[ ${py_fail} -eq 1 ]]; then
        cc_flags="${cc_flags} --with_error"
    fi
    py_flags="--file=${filename}"
    if [[ ${py_stop_on_error} -eq 1 ]]; then
        py_flags="${py_flags} --stop_on_error"
    fi

    rm -f ${filename}
    if [[ ${use_fifo} -eq 1 ]]; then
        mkfifo ${filename}
    fi
}

# Execute tests using FIFO.
use_fifo=1

no_threading-no_loop() {
    # Start Python binary in the background.
    ${py_client_cli} --no_threading --no_loop ${py_flags} &
    pid=$!
    # Execute C++.
    ${cc_bin} ${cc_bin_flags} ${cc_flags}
    # When this is done, Python client should exit.
    py-check wait ${pid}
}
sub-tests no_threading-no_loop

threading-no_loop() {
    ${py_client_cli} --no_loop ${py_flags} &
    pid=$!
    ${cc_bin} ${cc_bin_flags} ${cc_flags}
    py-check wait ${pid}
}
sub-tests threading-no_loop

threading-loop() {
    ${py_client_cli} ${py_flags} &
    pid=$!
    rm -f ${done_file}
    ${cc_bin} ${cc_bin_flags} ${cc_flags}
    if [[ ${py_stop_on_error} -ne 1 ]]; then
        # If the client will not halt execution based on an error, execute C++
        # client once more.
        ${cc_bin} ${cc_bin_flags} ${cc_flags}
        # Ensure that we wait until the client is fully done.
        while [[ ! -f ${done_file} ]]; do
            pause
        done
        # Kill the client with Ctrl+C.
        # TODO(eric.cousineau): In script form, this generally works well (only
        # one interrupt needed); however, interactively we need a few more.
        while ps -p ${pid} > /dev/null; do
            kill -INT ${pid}
            pause
        done
    fi
    py-check wait ${pid}
}
sub-tests threading-loop


# Execute tests without FIFO.
use_fifo=0

no_fifo-no_threading-no_loop() {
    # Execute C++ first.
    ${cc_bin} ${cc_bin_flags} ${cc_flags}
    # Start Python binary to consume generated file.
    py-check ${py_client_cli} --no_threading --no_loop ${py_flags}
}
sub-tests no_fifo-no_threading-no_loop

no_fifo-threading-no_loop() {
    ${cc_bin} ${cc_bin_flags} ${cc_flags}
    py-check ${py_client_cli} --no_loop ${py_flags}
}
sub-tests no_fifo-threading-no_loop
