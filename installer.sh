#!/usr/bin/env sh

# shellcheck disable=SC3000-SC4000

set -e

## Color
if command -v tput > /dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
fi

## Check System
if [ "$(uname)" != 'Linux' ] && [ "$(uname)" != 'Darwin' ]; then
    echo "${RED}error: This script only support Linux or macOS!${RESET}"
    exit 1
fi

## Check Root
if [ "$(id -u)" != '0' ]; then
    echo "${RED}error: This script must be run as root!${RESET}"
    exit 1
fi

## Check Command
for tool in curl unzip; do
    if ! command -v $tool> /dev/null 2>&1; then
        tool_need="$tool"" ""$tool_need"
    fi
done
if [ -n "$tool_need" ]; then
    if command -v apt > /dev/null 2>&1; then
        command_install_tool="apt update; apt install $tool_need -y"
    elif command -v dnf > /dev/null 2>&1; then
        command_install_tool="dnf install $tool_need -y"
    elif command -v yum > /dev/null  2>&1; then
        command_install_tool="yum install $tool_need -y"
    elif command -v zypper > /dev/null 2>&1; then
        command_install_tool="zypper --non-interactive install $tool_need"
    elif command -v pacman > /dev/null 2>&1; then
        command_install_tool="pacman -Sy $tool_need --noconfirm"
    elif command -v apk > /dev/null 2>&1; then
        command_install_tool="apk add $tool_need"
    else
        echo "$RED""You should install ""$tool_need""then try again.""$RESET"
        exit 1
    fi
    if ! /bin/sh -c "$command_install_tool";then
        echo "$RED""Use system package manager to install ""$tool_need""failed,""$RESET"
        echo "$RED""You should install ""$tool_need""then try again.""$RESET"
        exit 1
    fi
fi

notice_installled_tool() {
    if [ -n "$tool_need" ]; then
        echo "${GREEN}You have installed the following tools during installation:${RESET}"
        echo "$tool_need"
        echo "${GREEN}You can uninstall them now if you want.${RESET}"
    fi
}

check_arch_and_os() {
    if [ "$(uname)" = 'Linux' ]; then
        SYSTEM='linux'
        case "$(uname -m)" in
            'x86_64' | 'amd64')
                ARCH='amd64'
                ;;
            'i386' | 'i686')
                ARCH='386'
                ;;
            'armv5tel')
                ARCH='armv5'
                ;;
            'armv6l')
                ARCH='armv6'
                ;;
            'armv7l')
                ARCH='armv7'
                ;;
            'armv8' | 'aarch64')
                ARCH='arm64'
                ;;
            'mips')
                ARCH='mips'
                ;;
            'mipsle')
                ARCH='mipsle'
                ;;
            'mips64')
                ARCH='mips64'
                ;;
            'mips64le')
                ARCH='mips64le'
                ;;
            'ppc64le')
                ARCH='ppc64le'
                ;;
            'riscv64')
                ARCH='riscv64'
                ;;
            *)
                echo "${RED}error: Unsupported architecture: $(uname -m)${RESET}"
                exit 1
                ;;
        esac
        if [ "$ARCH" = 'amd64' ]; then
            if cat /proc/cpuinfo | grep avx2 > /dev/null 2>&1; then
                ARCH='x86_64_v3_avx2'
            elif cat /proc/cpuinfo | grep sse > /dev/null 2>&1; then
                ARCH='x86_64_v2_sse'
            else
                ARCH='x86_64'
            fi
        fi
    fi
    if [ "$(uname)" = 'Darwin' ]; then
        SYSTEM='macos'
        case "$(uname -m)" in
            'x86_64' | 'amd64')
                ARCH='x86_64'
                ;;
            'arm64')
                ARCH='arm64'
                ;;
            *)
                echo "${RED}error: Unsupported architecture: $(uname -m)${RESET}"
                exit 1
                ;;
        esac
    fi
}

check_version() {
    if [ -z "$JUICITY_VERSION" ]; then
        JUICITY_VERSION=$(curl -s https://api.github.com/repos/juicity/juicity/releases/latest | grep 'tag_name' | cut -d\" -f4)
        LOCAL_VERSION="$(/usr/local/bin/juicity-server -v | awk '{print $3}')" || LOCAL_VERSION=0
        [ "$JUICITY_VERSION" = "$LOCAL_VERSION" ] && echo "$GREEN""Latest version $JUICITY_VERSION already installed.""$RESET" && exit 0 || echo "$GREEN""Upgrading juicity from $LOCAL_VERSION to $JUICITY_VERSION...""$RESET"
    else
        echo "${YELLOW}warning: You are installing juicity version $JUICITY_VERSION${RESET}"
        LOCAL_VERSION=0
    fi

}

create_etc_juicity() {
    if [ ! -d /etc/juicity ]; then
        mkdir -p /usr/local/etc/juicity
    fi
}

download_juicity() {
    JUICITY_DOWNLOAD_URL="https://github.com/juicity/juicity/releases/download/$JUICITY_VERSION/juicity-$SYSTEM-$ARCH.zip"
    JUICITY_HASH_URL=$JUICITY_DOWNLOAD_URL.dgst
    JUICITY_DOWNLOAD_TMP_FILE="/tmp/juicity-$SYSTEM-$ARCH.zip"
    if ! curl -# -L -o "$JUICITY_DOWNLOAD_TMP_FILE" "$JUICITY_DOWNLOAD_URL"; then
        echo "${RED}error: Download juicity failed!${RESET}"
        exit 1
    fi
    if ! curl -s -L -o "$JUICITY_DOWNLOAD_TMP_FILE.dgst" "$JUICITY_HASH_URL"; then
        echo "${RED}error: Download juicity hash failed!${RESET}"
        exit 1
    fi
    local_sha256="$(sha256sum "$JUICITY_DOWNLOAD_TMP_FILE" | cut -d' ' -f1)"
    remote_sha256="$(cat "$JUICITY_DOWNLOAD_TMP_FILE.dgst" | grep sha256 | awk '{print $1}')"
    if [ "$local_sha256" != "$remote_sha256" ]; then
        echo "${RED}error: Check juicity hash failed!${RESET}"
        exit 1
    fi
}

download_systemd_service() (
    JUICITY_SERVICE_URL="https://raw.githubusercontent.com/juicity/juicity/master/systemd/juicity-server.service"
    JUICITY_SERVICE_TMP_FILE="/tmp/juicity-server.service"
    if ! curl -# -L -o "$JUICITY_SERVICE_TMP_FILE" "$JUICITY_SERVICE_URL"; then
        echo "${RED}error: Download juicity service file failed!${RESET}"
        exit 1
    fi
    JUICITY_CLIENT_SERVICE_URL="https://raw.githubusercontent.com/juicity/juicity/master/systemd/juicity-client.service"
    JUICITY_CLIENT_SERVICE_TMP_FILE="/tmp/juicity-client.service"
    if ! curl -# -L -o "$JUICITY_CLIENT_SERVICE_TMP_FILE" "$JUICITY_CLIENT_SERVICE_URL"; then
        echo "${RED}error: Download juicity client service file failed!${RESET}"
        exit 1
    fi
    mv juicity-server.service /etc/systemd/system/juicity-server.service
    mv juicity-client.service /etc/systemd/system/juicity-client.service
    systemctl daemon-reload
)

download_openrc_service() (
    JUICITY_SERVICE_URL="https://raw.githubusercontent.com/juicity/juicity/master/openrc/juicity-server"
    JUICITY_SERVICE_TMP_FILE="/tmp/juicity-server"
    if ! curl -# -L -o "$JUICITY_SERVICE_TMP_FILE" "$JUICITY_SERVICE_URL"; then
        echo "${RED}error: Download juicity service file failed!${RESET}"
        exit 1
    fi
    JUICITY_CLIENT_SERVICE_URL="https://raw.githubusercontent.com/juicity/juicity/master/openrc/juicity-client"
    JUICITY_CLIENT_SERVICE_TMP_FILE="/tmp/juicity-client"
    if ! curl -# -L -o "$JUICITY_CLIENT_SERVICE_TMP_FILE" "$JUICITY_CLIENT_SERVICE_URL"; then
        echo "${RED}error: Download juicity client service file failed!${RESET}"
        exit 1
    fi
    mv juicity-server /etc/init.d/juicity-server
    mv juicity-client /etc/init.d/juicity-client
    chmod +x /etc/init.d/juicity-server
    chmod +x /etc/init.d/juicity-client
)

download_service() {
    if command -v systemctl > /dev/null 2>&1; then
        download_systemd_service
    elif [ -f /sbin/openrc-run ]; then
        download_openrc_service
    else
        echo "${YELLOW}warning: You are not using systemd or OpenRC, you need to manually configure the service file.${RESET}"
    fi
}

stop_juicity() {
    if [ "$(systemctl is-active juicity-server)" = 'active' ]; then
        systemctl stop juicity-server
        juicity_server_stopped=1
    fi
    if [ "$(systemctl is-active juicity-client)" = 'active' ]; then
        systemctl stop juicity-client
        juicity_client_stopped=1
    fi
    if [ -f /sbin/openrc-run ] && [ -f /run/juicity-server.pid ]; then
        rc-service juicity-server stop
        juicity_server_stopped=1
    fi
    if [ -f /sbin/openrc-run ] && [ -f /run/juicity-client.pid ]; then
        rc-service juicity-client stop
        juicity_client_stopped=1
    fi
}

install_juicity() {
    tmp_dir=$(mktemp -d)
    unzip -o "$JUICITY_DOWNLOAD_TMP_FILE" -d "$tmp_dir"
    mv "$tmp_dir/juicity-server" /usr/local/bin/juicity-server
    chmod +x /usr/local/bin/juicity-server
    mv "$tmp_dir/juicity-client" /usr/local/bin/juicity-client
    chmod +x /usr/local/bin/juicity-client
    rm -rf "$tmp_dir"
}

start_juicity() {
    if [ "$juicity_server_stopped" = '1' ]; then
        if [ -f /sbin/openrc-run ]; then
            rc-service juicity-server start
        elif command -v systemctl > /dev/null 2>&1; then
            systemctl start juicity-server
        fi
    fi
    if [ "$juicity_client_stopped" = '1' ]; then
        if [ -f /sbin/openrc-run ]; then
            rc-service juicity-client start
        elif command -v systemctl > /dev/null 2>&1; then
            systemctl start juicity-client
        fi
    fi
}

main (){
    check_arch_and_os
    check_version
    create_etc_juicity
    download_juicity
    download_service
    stop_juicity
    install_juicity
    start_juicity
    echo "${GREEN}Installed successfully!${RESET}"
    notice_installled_tool
}

main