#!/usr/bin/env bash
#
# Define various aliases for containers. This script must be sourced to be
# useful.
$(return 1>/dev/null 2>&1)
if [[ $? -ne 0 ]]; then
    echo "This script must be sourced." 1>&2
    exit 1
fi


# Common variables
ARG_USER=(--userns keep-id --user "$(id -u):$(id -g)")
DEV_USB_NUM=0
REGISTRY="registry.gitlab.com/c8160/embedded-rust"

# Helper functions for dynamic evaluation

# Returns the root of the git project that $PWD is in. If $PWD is not within
# any git project, returns $PWD instead.
function __gitroot {
    GITROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo -e "\e[0;31m!! Not in a git repository. Mounting '$PWD' instead\e[0m" 1>&2
        pwd
    else
        echo $GITROOT
    fi
}

# Determine a suitable container runtime
#
# Defaults to podman if available, uses docker otherwise. If neither can be
# found, exits with an error.
function __crt {
    candidates=(podman docker)
    for c in $candidates; do
        CRT=$(command -v "$c" 2>&1)
        if [[ $? -eq 0 ]]; then
            echo $CRT
            return 0
        fi
    done

    echo "No suitable container runtime found!" 1>&2
    echo "Install either of:" 1>&2
    echo "- podman" 1>&2
    echo "- docker" 1>&2
    exit 127
}

function _vol_pwd {
    echo -v "$PWD:/project:z" -w "/project"
}

function _vol_gitroot {
    GR=$(__gitroot)
    echo -v "${GR}:${GR}:z" -w "$PWD"
}

function _vol_gitroot_ro {
    GR=$(__gitroot)
    echo -v "${GR}:${GR}:ro" -w "$PWD"
}

function _vol_cargo {
    echo -v esp32-cargo:/usr/local/share/cargo
}

function _dev_ttyusb {
    TTYS=$(echo /dev/ttyUSB* 2>/dev/null)
    if [[ -z "$TTYS" ]]; then
        echo "No USB devices found!" 1>&2
    else
        TTYS=$(echo $TTYS | xargs printf "--device %s ")
    fi
    echo --security-opt label\=disable $TTYS
}

function _dev_bus_usb {
    echo --security-opt label\=disable -v /dev/bus/usb:/dev/bus/usb
}

function _no_log {
    echo --log-driver none
}

function __disclaimer {
    YELLOW="\e[0;33m"
    RESET="\e[0m"
    echo ""
    echo -e "${YELLOW}>>> Running '$1' via alias <<<"
    echo ""
    echo -en "$RESET"
}

function espflash {
    __disclaimer "$0"
    $(__crt) run --rm -it \
        $(_dev_ttyusb) \
        $(_vol_gitroot_ro) \
        $(_no_log) \
        $REGISTRY/espflash:1.5.1 \
        "$@"
}

function espmonitor {
    __disclaimer "$0"
    $(__crt) run --rm -it \
        $(_dev_ttyusb) \
        $(_vol_gitroot_ro) \
        $(_no_log) \
        $REGISTRY/espmonitor:0.10.0 \
        "$@"
}

function esprust-analyzer {
    $(__crt) run --rm -i \
        $(_vol_gitroot) \
        $(_vol_cargo) \
        $(_no_log) \
        $REGISTRY/rust-xtensa32:1.62.1-nightly \
        rust-analyzer "$@"
}

function espcargo {
    $(__crt) run --rm -it \
        $(_vol_gitroot) \
        $(_vol_cargo) \
        $(_no_log) \
        $REGISTRY/rust-xtensa32:1.62.1-nightly \
        cargo "$@"
}

function espopenocd {
    __disclaimer "$0"
    $(__crt) run --rm -it \
        $(_vol_gitroot_ro) \
        $(_dev_bus_usb) \
        $(_no_log) \
        -p 3333:3333 \
        $REGISTRY/openocd-esp32:0.11.0 \
        "$@"
}

function espgdb {
    __disclaimer "$0"
    $(__crt) run --rm -it \
        $(_vol_gitroot_ro) \
        $(_vol_cargo) \
        $(_no_log) \
        --network host \
        $REGISTRY/gdb-xtensa32:esp-2021r2-patch3 \
        "$@"
}

export PATH="$(dirname $(readlink -f $0))/bin:$PATH"

function podalias {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "unset")
                unset -f __crt
                unset -f __disclaimer
                unset -f __gitroot
                unset -f espcargo
                unset -f espflash
                unset -f espgdb
                unset -f espmonitor
                unset -f espopenocd
                unset -f "$0"
                echo "Aliases removed"
                ;;
            *)
                echo "Unknown argument '$1'" 1>&2
                ;;
        esac
    fi
}

echo "Aliases have been sourced"
