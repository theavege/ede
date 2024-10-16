function log
{
    declare -rAi TAG=(
        [error]=31
        [info]=32
        [audit]=33
    )
    printf '%(%y-%m-%d_%T)T\x1b[%dm\t%s:\t%b\x1b[0m\n' -1 "${TAG[${1,,:?}]}" "${1^^}" "${2:?}" 1>&2
    if [[ ${1} == 'error' ]]; then
        return 1
    fi
}

function main
{
    set -euo pipefail
    if [[ ${RUNNER_OS} == "Linux" ]]; then
        git submodule update --init --recursive
        sudo apt-get update
        sudo apt-get install -y asciidoc xorg fltk1.3-dev jam libdbus-1-dev
        for item in "edelib" "."; do
            pushd "${item}" || return 1
            log 'info' "Build ${PWD}"
            bash autogen.sh
            bash configure
            jam
            sudo jam install
            popd
        done;
    fi > /dev/null
}

main
