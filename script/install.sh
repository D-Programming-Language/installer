#!/usr/bin/env bash
#
# Copyright: Copyright Martin Nowak 2015 -.
# License: Boost License 1.0 (www.boost.org/LICENSE_1_0.txt)
# Authors: Martin Nowak

_() {
set -ueo pipefail

# ------------------------------------------------------------------------------

log_() {
    local tilde='~'
    echo "${@//$HOME/$tilde}"
}

log() {
    if [ "$verbosity" -gt 0 ]; then
        log_ "$@"
    fi
}

logV() {
    if [ "$verbosity" -gt 1 ]; then
        log_ "$@"
    fi
}

logE() {
    log_ "$@" >&2
}

fatal() {
    logE "$@"
    exit 1
}

# ------------------------------------------------------------------------------
curl2() {
    : ${CURL_USER_AGENT:="installer/install.sh $(command curl --version | head -n 1)"}
    TIMEOUT_ARGS="--connect-timeout 5 --speed-time 30 --speed-limit 1024"
    command curl $TIMEOUT_ARGS -fL -A "$CURL_USER_AGENT" "$@"
}

curl() {
    if [ "$verbosity" -gt 0 ]; then
        curl2 -# "$@"
    else
        curl2 -sS "$@"
    fi
}

retry() {
    for i in {0..4}; do
        if "$@"; then
            break
        elif [ $i -lt 4 ]; then
            sleep $((1 << $i))
        else
            fatal "Failed to download '$url'"
        fi
    done
}

# url path
download() {
    local url=$1
    local path=$2

    retry curl "$url" -o "$path"
}

# url
fetch() {
    local url=$1
    local path=$(mktemp "$TMP_ROOT/XXXXXX")

    retry curl2 -sS "$url" -o "$path"
    cat "$path"
    rm "$path"
}

# ------------------------------------------------------------------------------

command=
compiler=dmd
verbosity=1
path=~/dlang
case $(uname -s) in
    Darwin) os=osx;;
    Linux) os=linux;;
    FreeBSD) os=freebsd;;
    *)
        fatal "Unsupported OS $(uname -s)"
        ;;
esac
case $(uname -m) in
    x86_64|amd64) arch=x86_64; model=64;;
    i*86) arch=x86; model=32;;
    *)
        fatal "Unsupported Arch $(uname -m)"
        ;;
esac

check_tools() {
    while [[ $# > 0 ]]; do
        if ! command -v $1 &>/dev/null &&
                # detect OSX' liblzma support in libarchive
                ! { [ $os-$1 == osx-xz ] && otool -L /usr/lib/libarchive.*.dylib | grep -qF liblzma; }; then
            local msg="Required tool $1 not found, please install it."
            case $os-$1 in
                osx-xz) msg="$msg http://macpkg.sourceforge.net";;
            esac
            fatal "$msg"
        fi
        shift
    done
}

# ------------------------------------------------------------------------------

mkdir -p "$path"
TMP_ROOT=$(mktemp -d "$path/.installer_tmp_XXXXXX")

mkdtemp() {
    mktemp -d "$TMP_ROOT/XXXXXX"
}

cleanup() {
    rm -rf "$TMP_ROOT";
}
trap cleanup EXIT

# ------------------------------------------------------------------------------

usage() {
    log 'Usage

  install.sh [<command>] [<args>]

Commands

  install       Install a D compiler (default command)
  uninstall     Remove an installed D compiler
  list          List all installed D compilers
  update        Update this dlang script

Options

  -h --help     Show this help
  -p --path     Install location (default ~/dlang)
  -v --verbose  Verbose output

Run "install.sh <command> --help to get help for a specific command.
If no argument are provided, the latest DMD compiler will be installed.
'
}

command_help() {
    local _compiler='Compiler

  dmd|gdc|ldc           latest version of a compiler
  dmd|gdc|ldc-<version> specific version of a compiler (e.g. dmd-2.071.1, ldc-1.1.0-beta2)
  dmd|ldc-beta          latest beta version of a compiler
  dmd-nightly           latest dmd nightly
  dmd-2016-08-08        specific dmd nightly
'

    case $1 in
        install)
            log 'Usage

  install.sh install <compiler>

Description

  Download and install a D compiler.
  By default the latest release of the DMD compiler is selected.

Options

  -a --activate     Only print the path to the activate script

Examples

  install.sh
  install.sh dmd
  install.sh install dmd
  install.sh install dmd-2.071.1
  install.sh install ldc-1.1.0-beta2
'
            log "$_compiler"
            ;;

        uninstall)
            log 'Usage

  install.sh uninstall <compiler>

Description

  Uninstall a D compiler.

Examples

  install.sh uninstall dmd
  install.sh uninstall dmd-2.071.1
  install.sh uninstall ldc-1.1.0-beta2
'
            log "$_compiler"
            ;;

        list)
            log 'Usage

  install.sh list

Description

  List all installed D compilers.
'
            ;;

        update)
            log 'Usage

  install.sh update

Description

  Update the dlang installer itself.
'
    esac
}

# ------------------------------------------------------------------------------

parse_args() {
    local _help=
    local _activate=

    while [[ $# > 0 ]]; do
        case "$1" in
            -h | --help)
                _help=1
                ;;

            -p | --path)
                if [ -z "${2:-}" ]; then
                    fatal '-p|--path must be followed by a path.';
                fi
                path="$2"
                ;;

            -v | --verbose)
                verbosity=2
                ;;

            -a | --activate)
                _activate=1
                ;;

            use | install | uninstall | list | update)
                command=$1
                ;;

            remove)
                command=uninstall
                ;;

            dmd | dmd-* | gdc | gdc-* | ldc | ldc-*)
                compiler=$1
                ;;
        esac
        shift
    done

    if [ -n "$_help" ]; then
        [ -z "$command" ] && usage || command_help $command
        exit 0
    fi
    if [ -n "$_activate" ]; then
       if [ "${command:-install}" == "install" ]; then
           verbosity=0
       else
           [ -z "$command" ] && usage || command_help $command
           exit 1
       fi
    fi
}

# ------------------------------------------------------------------------------

# run_command command [compiler]
run_command() {
    case $1 in
        install)
            local has_dub_included=0
            check_tools curl
            if [ ! -f "$path/install.sh" ]; then
                install_dlang_installer
            fi
            if [ -z "${2:-}" ]; then
                fatal "Missing compiler argument for $1 command.";
            fi
            if [ -d "$path/$2" ]; then
                log "$2 already installed";
            else
                install_compiler $2
                has_dub_included=$?
            fi
            if [ "$has_dub_included" -eq 0 ] ; then
                install_dub
            fi
            write_env_vars $2

            if [ $(basename $SHELL) = fish ]; then
                local suffix=.fish
            fi
            if [ "$verbosity" -eq 0 ]; then
                echo "$path/$2/activate${suffix:-}"
            else
                log "
Run \`source $path/$2/activate${suffix:-}\` in your shell to use $2.
This will setup PATH, LIBRARY_PATH, LD_LIBRARY_PATH, DMD, DC, and PS1.
Run \`deactivate\` later on to restore your environment."
            fi
            ;;

        uninstall)
            if [ -z "${2:-}" ]; then
                fatal "Missing compiler argument for $1 command.";
            fi
            uninstall_compiler $2
            ;;

        list)
            if [ -n "${2:-}" ]; then
                log "Ignoring compiler argument '$2' for list command.";
            fi
            list_compilers
            ;;

        update)
            install_dlang_installer
            ;;
    esac
}

install_dlang_installer() {
    mkdir -p "$path"
    local url=https://dlang.org/install.sh
    logV "Downloading $url"
    download "$url" "$path/install.sh"
    chmod +x "$path/install.sh"
    log "The latest version of this script was installed as $path/install.sh.
It can be used it to install further D compilers.
Run \`$path/install.sh --help\` for usage information.
"
}

resolve_latest() {
    case $compiler in
        dmd)
            local url=http://downloads.dlang.org/releases/LATEST
            logV "Determing latest dmd version ($url)."
            compiler="dmd-$(fetch $url)"
            ;;
        dmd-beta)
            local url=http://downloads.dlang.org/pre-releases/LATEST
            logV "Determing latest dmd-beta version ($url)."
            compiler="dmd-$(fetch $url)"
            ;;
        dmd-*) # nightly master or feature branch
            # dmd-nightly, dmd-master, dmd-branch
            # but not: dmd-2016-10-19 or dmd-branch-2016-10-20
            #          dmd-2.068.0 or dmd-2.068.2-5
            if [[ ! $compiler =~ -[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
               [[ ! $compiler =~ -[0-9][.][0-9]{3}[.][0-9]{1,3}(-[0-9]{1,3})? ]]
            then
                local url=http://nightlies.dlang.org/$compiler/LATEST
                logV "Determing latest $compiler version ($url)."
                compiler="dmd-$(fetch $url)"
            fi
            ;;
        ldc)
            local url=https://ldc-developers.github.io/LATEST
            logV "Determing latest ldc version ($url)."
            compiler="ldc-$(fetch $url)"
            ;;
        ldc-beta)
            local url=https://ldc-developers.github.io/LATEST_BETA
            logV "Determining latest ldc-beta version ($url)."
            compiler="ldc-$(fetch $url)"
            ;;
        gdc)
            local url=http://gdcproject.org/downloads/LATEST
            logV "Determing latest gdc version ($url)."
            compiler="gdc-$(fetch $url)"
            ;;
    esac
}

install_compiler() {
    local has_dub_included=0

    # dmd-2.065, dmd-2.068.0, dmd-2.068.1-b1
    if [[ $1 =~ ^dmd-2\.([0-9]{3})(\.[0-9])?(-.*)?$ ]]; then
        local basename="dmd.2.${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        local ver="2.${BASH_REMATCH[1]}"

        if [[ $ver > "2.064z" ]]; then
            basename="$basename.$os"
            ver="$ver${BASH_REMATCH[2]}"
            if [ $os = freebsd ]; then
                basename="$basename-$model"
            fi
        fi

        if [[ $ver > "2.068.0z" ]]; then
            local arch="tar.xz"
        else
            local arch="zip"
        fi

        if [[ $ver > "2.072.0z" ]]; then
            has_dub_included=1
        fi

        if [ -n "${BASH_REMATCH[3]}" ]; then # pre-release
            local url="http://downloads.dlang.org/pre-releases/2.x/$ver/$basename.$arch"
        else
            local url="http://downloads.dlang.org/releases/2.x/$ver/$basename.$arch"
        fi

        download_and_unpack "$url" "$path/$1" "$url.sig"

    # dmd-2015-11-20, dmd-feature_branch-2016-10-20
    elif [[ $1 =~ ^dmd(-(.*))?-[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        local branch=${BASH_REMATCH[2]:-master}
        local basename="dmd.$branch.$os"
        if [ $os = freebsd ]; then
            basename="$basename-$model"
        fi
        local url="http://nightlies.dlang.org/$1/$basename.tar.xz"

        download_and_unpack "$url" "$path/$1" "$url.sig"

    # ldc-0.12.1 or ldc-0.15.0-alpha1
    elif [[ $1 =~ ^ldc-([0-9]+\.[0-9]+\.[0-9]+(-.*)?)$ ]]; then
        local ver=${BASH_REMATCH[1]}
        local url="https://github.com/ldc-developers/ldc/releases/download/v$ver/ldc2-$ver-$os-$arch.tar.xz"
        if [ $os != linux ] && [ $os != osx ]; then
            fatal "no ldc binaries available for $os"
        fi
        if [[ $ver > "1.1.0z" ]]; then
            has_dub_included=1
        fi

        download_and_unpack "$url" "$path/$1"

    # gdc-4.8.2, gdc-4.9.0-alpha1, gdc-5.2, or gdc-5.2-alpha1
    elif [[ $1 =~ ^gdc-([0-9]+\.[0-9]+(\.[0-9]+)?(-.*)?)$ ]]; then
        local name=${BASH_REMATCH[0]}
        if [ $os != linux ]; then
            fatal "no gdc binaries available for $os"
        fi
        case $arch in
            x86_64) local triplet=x86_64-linux-gnu;;
            x86) local triplet=i686-linux-gnu;;
        esac
        local url="http://gdcproject.org/downloads/binaries/$triplet/$name.tar.xz"

        download_and_unpack "$url" "$path/$1"

        url=https://raw.githubusercontent.com/D-Programming-GDC/GDMD/master/dmd-script
        log "Downloading gdmd $url"
        download "$url" "$path/$1/bin/gdmd"
        chmod +x "$path/$1/bin/gdmd"

    else
        fatal "Unknown compiler '$1'"
    fi

    return "$has_dub_included"
}

find_gpg() {
    if command -v gpg2 &>/dev/null; then
        echo gpg2
    elif command -v gpg &>/dev/null; then
        echo gpg
    else
        echo "Warning: No gpg tool found to verify downloads." >&2
        echo x
    fi
}

# url, path, [verify]
download_and_unpack() {
    local tmp=$(mkdtemp)
    local name="$(basename $1)"

    check_tools curl
    if [[ $name =~ \.tar\.xz$ ]]; then
        check_tools tar xz
    else
        check_tools unzip
    fi

    log "Downloading and unpacking $1"
    download "$1" "$tmp/$name"
    if [ ! -z ${3:-} ]; then
        verify "$3" "$tmp/$name"
    fi
    if [[ $name =~ \.tar\.xz$ ]]; then
        tar --strip-components=1 -C "$tmp" -Jxf "$tmp/$name"
    else
        unzip -q -d "$tmp" "$tmp/$name"
        mv "$tmp/dmd2"/* "$tmp/"
        rmdir "$tmp/dmd2"
    fi
    rm "$tmp/$name"
    mv "$tmp" "$2"
}

verify() {
    : ${GPG:=$(find_gpg)}
    if [ $GPG = x ]; then
        return
    fi
    if [ ! -f "$path/d-keyring.gpg" ]; then
        log "Downloading https://dlang.org/d-keyring.gpg"
        download https://dlang.org/d-keyring.gpg "$path/d-keyring.gpg"
    fi
    if ! $GPG -q --verify --keyring "$path/d-keyring.gpg" --no-default-keyring <(fetch "$1") "$2" 2>/dev/null; then
        fatal "Invalid signature $1"
    fi
}

write_env_vars() {
    case $1 in
        dmd*)
            [ $os = osx ] && local suffix= || local suffix=$model
            local binpath=$os/bin$suffix
            local libpath=$os/lib$suffix
            local dc=dmd
            local dmd=dmd
            ;;

        ldc*)
            local binpath=bin
            local libpath=lib
            local dc=ldc2
            local dmd=ldmd2
            ;;

        gdc*)
            local binpath=bin
            local libpath=lib;
            local dc=gdc
            local dmd=gdmd
            ;;
    esac

    logV "Writing environment variables to $path/$1/activate"
    cat > "$path/$1/activate" <<EOF
deactivate() {
    export PATH="\$_OLD_D_PATH"
    export LIBRARY_PATH="\$_OLD_D_LIBRARY_PATH"
    export LD_LIBRARY_PATH="\$_OLD_D_LD_LIBRARY_PATH"
    export PS1="\$_OLD_D_PS1"

    unset _OLD_D_PATH
    unset _OLD_D_LIBRARY_PATH
    unset _OLD_D_LD_LIBRARY_PATH
    unset _OLD_D_PS1
    unset DMD
    unset DC
    unset -f deactivate
}

_OLD_D_PATH="\${PATH:-}"
_OLD_D_LIBRARY_PATH="\${LIBRARY_PATH:-}"
_OLD_D_LD_LIBRARY_PATH="\${LD_LIBRARY_PATH:-}"
_OLD_D_PS1="\${PS1:-}"

export PATH="$path/dub:$path/$1/$binpath:\${PATH:-}"
export LIBRARY_PATH="$path/$1/$libpath:\${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$path/$1/$libpath:\${LD_LIBRARY_PATH:-}"
export DMD=$dmd
export DC=$dc
export PS1="($1)\${PS1:-}"
EOF

    logV "Writing environment variables to $path/$1/activate.fish"
    cat > "$path/$1/activate.fish" <<EOF
function deactivate
    set -gx PATH \$_OLD_D_PATH
    set -gx LIBRARY_PATH \$_OLD_D_LIBRARY_PATH
    set -gx LD_LIBRARY_PATH \$_OLD_D_LD_LIBRARY_PATH

    functions -e fish_prompt
    functions -c _old_d_fish_prompt fish_prompt
    functions -e _old_d_fish_prompt

    set -e _OLD_D_PATH
    set -e _OLD_D_LIBRARY_PATH
    set -e _OLD_D_LD_LIBRARY_PATH
    set -e DMD
    set -e DC
    functions -e deactivate
end

set -g _OLD_D_PATH \$PATH
set -g _OLD_D_LIBRARY_PATH \$LIBRARY_PATH
set -g _OLD_D_LD_LIBRARY_PATH \$LD_LIBRARY_PATH
set -g _OLD_D_PS1 \$PS1

set -gx PATH "$path/dub" "$path/$1/$binpath" \$PATH
set -gx LIBRARY_PATH "$path/$1/$libpath" \$LIBRARY_PATH
set -gx LD_LIBRARY_PATH "$path/$1/$libpath" \$LD_LIBRARY_PATH
set -gx DMD $dmd
set -gx DC $dc
functions -c fish_prompt _old_d_fish_prompt
function fish_prompt
    printf '($1)%s' (_old_d_fish_prompt)
end
EOF
}

uninstall_compiler() {
    if [ ! -d "$path/$1" ]; then
        fatal "$1 is not installed in $path"
    fi
    log "Removing $path/$1"
    rm -rf "$path/$1"
}

list_compilers() {
    check_tools egrep
    if [ -d "$path" ]; then
        ls "$path" | egrep -v '^dub|^install\.sh|^d-keyring\.gpg'
    fi
}

install_dub() {
    if [ $os != linux ] && [ $os != osx ]; then
        log "no dub binaries available for $os"
        return
    fi
    local url=http://code.dlang.org/download/LATEST
    logV "Determing latest dub version ($url)."
    dub="dub-$(fetch $url)"
    if [ -d "$path/$dub" ]; then
        log "$dub already installed"
        return
    fi
    local tmp=$(mkdtemp)
    local url="http://code.dlang.org/files/$dub-$os-$arch.tar.gz"

    log "Downloading and unpacking $url"
    download "$url" "$tmp/dub.tar.gz"
    tar -C "$tmp" -zxf "$tmp/dub.tar.gz"
    logV "Removing old dub versions"
    rm -rf "$path/dub" "$path/dub-*"
    mv "$tmp" "$path/$dub"
    logV "Linking $path/dub -> $path/$dub"
    ln -s $dub "$path/dub"
}

# ------------------------------------------------------------------------------

parse_args "$@"
resolve_latest $compiler
run_command ${command:-install} $compiler
}

_ "$@"
