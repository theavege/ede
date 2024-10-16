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
        sudo apt-get install --yes --no-install-recommends build-essential auto{conf,tools-dev} curl xorg fltk1.3-dev jam libdbus-1-dev
        export PYTHON=$(which python2)
        for item in "edelib" "."; do
            pushd "${item}" || return 1
            log 'info' "Autogen ${PWD}"
            bash autogen.sh
            log 'info' "Configure ${PWD}"
            bash configure
            log 'info' "Jam ${PWD}"
            jam || true
            log 'info' "Jam Install ${PWD}"
            sudo jam install || true
            popd
        done;
    fi > /dev/null
}

main
