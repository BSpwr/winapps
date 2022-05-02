#!/usr/bin/env bash

_wa_usage() {
    echo "Usage:
  $0 install --user    # Install everything in ${HOME}
  $0 install --system  # Install everything in /usr"
    exit 1
}

_wa_no_sudo() {
    echo "You are attempting to switch from a --system install to a --user install.
Please run \"$0 install --system --uninstall\" first."
    exit
}

_wa_install() {
    ${SUDO} mkdir -p "${SYS_PATH}/apps"
    source "${path_script}/winapps" install
}

_wa_find_installed() {
    echo -n "  Checking for installed apps in RDP machine (this may take a while)..."
    if [ "${USEDEMO:-0}" != 1 ]; then
        rm -f "${HOME}"/.local/share/winapps/installed.bat
        rm -f "${HOME}"/.local/share/winapps/installed.tmp
        rm -f "${HOME}"/.local/share/winapps/installed
        rm -f "${HOME}"/.local/share/winapps/detected
        cp "${path_script}/ExtractPrograms.ps1" "${HOME}"/.local/share/winapps/ExtractPrograms.ps1
        for F in "${path_script}/../apps/"*; do
            [ -d "${F}" ] || continue
            source "${F}/info"
            F=${F##*/}
            echo "IF EXIST \"${WIN_EXECUTABLE}\" ECHO ${F} >> \\\\tsclient\\home\\.local\\share\\winapps\\installed.tmp" >>"${HOME}"/.local/share/winapps/installed.bat
        done
        echo "powershell.exe -ExecutionPolicy Bypass -File \\\\tsclient\\home\\.local\\share\\winapps\\ExtractPrograms.ps1 > \\\\tsclient\home\\.local\\share\\winapps\\detected" >>"${HOME}"/.local/share/winapps/installed.bat
        echo "RENAME \\\\tsclient\\home\\.local\\share\\winapps\\installed.tmp installed" >>${HOME}/.local/share/winapps/installed.bat
        # xfreerdp_opt="xfreerdp ${RDP_FLAGS} /d:${RDP_DOMAIN} /u:${RDP_USER} /p:${RDP_PASS} /v:${RDP_IP} +auto-reconnect +clipboard +home-drive -wallpaper /scale:${RDP_SCALE} /dynamic-resolution"
        xfreerdp /d:"${RDP_DOMAIN}" /u:"${RDP_USER}" /p:"${RDP_PASS}" /v:"${RDP_IP}" -decorations /cert:ignore +auto-reconnect +home-drive -wallpaper /span /wm-class:"RDPInstaller" /app:"C:\Windows\System32\cmd.exe" /app-icon:"${path_script}/../docs/icons/windows.svg" /app-cmd:"/C \\\\tsclient\\home\\.local\\share\\winapps\\installed.bat" 1>/dev/null 2>&1 &
        COUNT=0
        while [ ! -f "${HOME}/.local/share/winapps/installed" ]; do
            sleep 5
            COUNT=$((COUNT + 1))
            if ((COUNT == 15)); then
                echo " Finished."
                echo ""
                echo "The RDP connection failed to connect or run. Please confirm FreeRDP can connect with:"
                echo "  winapps check"
                echo ""
                echo "If it cannot connect, this is most likely due to:"
                echo "  - You need to accept the security cert the first time you connect (with 'check')"
                echo "  - Not enabling RDP in the Windows VM"
                echo "  - Not being able to connect to the IP of the VM"
                echo "  - Incorrect user credentials in winapps.conf"
                echo "  - Not merging docs/RDPApps.reg into the VM"
                exit
            fi
        done
        if [ "${MAKEDEMO:-0}" = 1 ]; then
            rm -rf /tmp/winapps_demo
            cp -a "${HOME}"/.local/share/winapps /tmp/winapps_demo
            exit
        fi
    else
        rm -rf "${HOME}"/.local/share/winapps
        cp -a /tmp/winapps_demo "${HOME}"/.local/share/winapps
        #sleep 3
    fi
    echo " Finished."
}

_wa_config_app() {
    source "${SYS_PATH}/apps/${1}/info"
    echo -n "  Configuring ${NAME}..."
    if [ "${USEDEMO:-0}" != 1 ]; then
        ${SUDO} rm -f "${APP_PATH}/${1}.desktop"
        echo "[Desktop Entry]
Name=${NAME}
Exec=${BIN_PATH}/winapps ${1} %F
Terminal=false
Type=Application
Icon=${SYS_PATH}/apps/${1}/icon.${2}
StartupWMClass=${FULL_NAME}
Comment=${FULL_NAME}
Categories=${CATEGORIES}
MimeType=${MIME_TYPES}
" | ${SUDO} tee "${APP_PATH}/${1}.desktop" >/dev/null
        ${SUDO} rm -f "${BIN_PATH}/${1}"
        echo "#!/usr/bin/env bash
${BIN_PATH}/winapps ${1} $*
" | ${SUDO} tee "${BIN_PATH}/${1}" >/dev/null
        ${SUDO} chmod a+x "${BIN_PATH}/${1}"
    fi
    echo " Finished."
}

_wa_config_apps() {
    APPS=()
    for F in $(sed 's/\r/\n/g' "${HOME}/.local/share/winapps/installed"); do
        source "${path_script}/../apps/${F}/info"
        APPS+=("${FULL_NAME} (${F})")
        INSTALLED_EXES+=("$(echo "${WIN_EXECUTABLE##*\\}" | tr '[:upper:]' '[:lower:]')")
    done
    IFS=$'\n' APPS=($(sort <<<"${APPS[*]}"))
    unset IFS
    OPTIONS=("Set up all detected pre-configured applications" "Select which pre-configured applications to set up" "Do not set up any pre-configured applications")
    menuFromArr APP_INSTALL "How would you like to handle WinApps pre-configured applications?" "${OPTIONS[@]}"
    if [ "${APP_INSTALL}" = "Select which pre-configured applications to set up" ]; then
        checkbox_input "Which pre-configured apps would you like to set up?" APPS SELECTED_APPS
        echo "" >"${HOME}/.local/share/winapps/installed"
        for F in "${SELECTED_APPS[@]}"; do
            APP="${F##*(}"
            APP="${APP%%)}"
            echo "${APP}" >>"${HOME}/.local/share/winapps/installed"
        done
    fi
    ${SUDO} cp "${path_script}/winapps" "${BIN_PATH}/winapps"
    COUNT=0
    if [ "${APP_INSTALL}" != "Do not set up any pre-configured applications" ]; then
        for F in $(sed 's/\r/\n/g' "${HOME}/.local/share/winapps/installed"); do
            COUNT=$((COUNT + 1))
            ${SUDO} cp -r "apps/${F}" "${SYS_PATH}/apps"
            _wa_config_app "${F}" svg
        done
    fi
    rm -f "${HOME}/.local/share/winapps/installed"
    rm -f "${HOME}/.local/share/winapps/installed.bat"
    if ((COUNT == 0)); then
        echo "  No configured applications."
    fi
}

_wa_config_detected_apps() {
    if [ -f "${HOME}/.local/share/winapps/detected" ]; then
        sed -i 's/\r//g' "${HOME}/.local/share/winapps/detected"
        source "${HOME}/.local/share/winapps/detected"
        APPS=()
        for I in "${!NAMES[@]}"; do
            EXE=${EXES[$I]##*\\}
            EXE_LOWER=$(echo "${EXE}" | tr '[:upper:]' '[:lower:]')
            if (
                dlm=$'\x1F'
                IFS="$dlm"
                [[ "$dlm${INSTALLED_EXES[*]}$dlm" != *"$dlm${EXE_LOWER}$dlm"* ]]
            ); then
                APPS+=("${NAMES[$I]} (${EXE})")
            fi
        done
        IFS=$'\n' APPS=($(sort <<<"${APPS[*]}"))
        unset IFS
        OPTIONS=("Set up all detected applications" "Select which applications to set up" "Do not set up any applications")
        menuFromArr APP_INSTALL "How would you like to handle other detected applications?" "${OPTIONS[@]}"
        if [ "${APP_INSTALL}" = "Select which applications to set up" ]; then
            checkbox_input "Which other apps would you like to set up?" APPS SELECTED_APPS
            echo "" >"${HOME}/.local/share/winapps/installed"
            for F in "${SELECTED_APPS[@]}"; do
                EXE="${F##*(}"
                EXE="${EXE%%)}"
                APP="${F% (*}"
                echo "${EXE}|${APP}" >>"${HOME}/.local/share/winapps/installed"
            done
        elif [ "${APP_INSTALL}" = "Set up all detected applications" ]; then
            for I in "${!EXES[@]}"; do
                EXE=${EXES[$I]##*\\}
                echo "${EXE}|${NAMES[$I]}" >>"${HOME}/.local/share/winapps/installed"
            done
        fi
        COUNT=0
        if [ -f "${HOME}/.local/share/winapps/installed" ]; then
            while read -r LINE; do
                EXE="${LINE%|*}"
                NAME="${LINE#*|}"
                for I in "${!NAMES[@]}"; do
                    if [ "${NAME}" = "${NAMES[$I]}" ] && [[ "${EXES[$I]}" == *"\\${EXE}" ]]; then
                        EXE=$(echo "${EXE}" | tr '[:upper:]' '[:lower:]')
                        ${SUDO} mkdir -p "${SYS_PATH}/apps/${EXE}"
                        echo "# GNOME shortcut name
NAME=\"${NAME}\"

# Used for descriptions and window class
FULL_NAME=\"${NAME}\"

# The executable inside windows
WIN_EXECUTABLE=\"${EXES[$I]}\"

# GNOME categories
CATEGORIES=\"WinApps\"

# GNOME mimetypes
MIME_TYPES=\"\"
" >"${SYS_PATH}/apps/${EXE}/info"
                        echo "${ICONS[$I]}" | base64 -d >"${SYS_PATH}/apps/${EXE}/icon.ico"
                        _wa_config_app "${EXE}" ico
                        COUNT=$((COUNT + 1))
                    fi
                done
            done <"${HOME}/.local/share/winapps/installed"
            rm -f "${HOME}/.local/share/winapps/installed"
        fi
        rm -f "${HOME}/.local/share/winapps/installed.bat"
        if ((COUNT == 0)); then
            echo "  No configured applications."
        fi
    fi
}

_wa_config_windows() {
    echo -n "  Configuring Windows..."
    if [ "${USEDEMO:-0}" != 1 ]; then
        ${SUDO} rm -f "${APP_PATH}/windows.desktop"
        ${SUDO} mkdir -p "${SYS_PATH}/icons"
        ${SUDO} cp "${path_script}/../docs/icons/windows.svg" "${SYS_PATH}/icons/windows.svg"
        echo "[Desktop Entry]
Name=Windows
Exec=${BIN_PATH}/winapps windows %F
Terminal=false
Type=Application
Icon=${SYS_PATH}/icons/windows.svg
StartupWMClass=Microsoft Windows
Comment=Microsoft Windows
Categories=Windows
" | ${SUDO} tee "${APP_PATH}/windows.desktop" >/dev/null
        ${SUDO} rm -f "${BIN_PATH}/windows"
        echo "#!/usr/bin/env bash
${BIN_PATH}/winapps windows
" | ${SUDO} tee "${BIN_PATH}/windows" >/dev/null
        ${SUDO} chmod a+x "${BIN_PATH}/windows"
    fi
    echo " Finished."
}

_wa_uninstall_user() {
    echo "Uninstalling (user)..."
    rm -rf "${HOME}/.local/share/winapps" "${HOME}/.local/bin/winapps"
    for F in $(grep -l -d skip "bin/winapps" "${HOME}/.local/share/applications/"*); do
        echo -n "  Removing ${F}..."
        ${SUDO} rm "${F}"
        echo " Finished."
    done
    for F in $(grep -l -d skip "bin/winapps" "${HOME}/.local/bin/"*); do
        echo -n "  Removing ${F}..."
        ${SUDO} rm "${F}"
        echo " Finished."
    done
}

_wa_uninstall_sys() {
    echo "Uninstalling (system)..."
    ${SUDO} rm -rf "/usr/local/share/winapps" "/usr/local/bin/winapps"
    for F in $(grep -l -d skip "winapps" "/usr/share/applications/"*); do
        if [ -z "${SUDO}" ]; then
            _wa_no_sudo
        fi
        echo -n "  Removing ${F}..."
        ${SUDO} rm "${F}"
        echo " Finished."
    done
    for F in $(grep -l -d skip "winapps" "/usr/local/bin/"*); do
        if [ -z "${SUDO}" ]; then
            _wa_no_sudo
        fi
        echo -n "  Removing ${F}..."
        ${SUDO} rm "${F}"
        echo " Finished."
    done
}

_install_user() {
    SUDO=""
    BIN_PATH="${HOME}/.local/bin"
    APP_PATH="${HOME}/.local/share/applications"
    SYS_PATH="${HOME}/.local/share/winapps"
    [ -d "${BIN_PATH}" ] || mkdir -p "${BIN_PATH}"
    [ -d "${APP_PATH}" ] || mkdir -p "${APP_PATH}"
    [ -d "${SYS_PATH}" ] || mkdir -p "${SYS_PATH}"
}

_install_sys() {
    SUDO="sudo"
    sudo ls >/dev/null
    BIN_PATH="/usr/local/bin"
    APP_PATH="/usr/share/applications"
    SYS_PATH="/usr/local/share/winapps"
    [ -d "${BIN_PATH}" ] || $SUDO mkdir -p "${BIN_PATH}"
    [ -d "${APP_PATH}" ] || $SUDO mkdir -p "${APP_PATH}"
    [ -d "${SYS_PATH}" ] || $SUDO mkdir -p "${SYS_PATH}"
}

_debug_log() {
    if [ "${DEBUG}" = "true" ]; then
        echo "[$(date)-${RANDOM}] ${1}" >>"$path_share/winapps.log"
    fi
}

_installer() {
    path_script="$(cd "$(dirname "$0")" && pwd)"
    INSTALLED_EXES=()
    source "${path_script}/inquirer.sh"

    while [[ "${#}" -ge 0 ]]; do
        case "${1}" in
        -u | --user)
            _install_user
            break
            ;;
        -s | --system)
            _install_sys
            break
            ;;
        -d | --demo)
            USEDEMO=1
            ;;
        --uninstall)
            _wa_uninstall_user
            _wa_uninstall_sys
            ;;
        *)
            if [[ "${#}" -gt 0 ]]; then
                _wa_usage
                exit 1
            fi
            OPTIONS=(User System)
            menuFromArr INSTALL_TYPE "Would you like to install for the current user or the whole system?" "${OPTIONS[@]}"
            break
            ;;
        esac
        shift
    done

    echo "Removing any old configurations..."
    _wa_uninstall_user
    _wa_uninstall_sys

    echo "Installing..."
    # Inititialize
    _wa_install

    # Check for installed apps
    _wa_find_installed

    # Install windows
    _wa_config_windows

    # Configure apps
    _wa_config_apps
    _wa_config_detected_apps

    echo "Installation complete."
}

main() {
    path_script="$(cd "$(dirname "$0")" && pwd)"
    path_conf="${HOME}/.config/winapps"
    path_share="${HOME}/.local/share/winapps"
    file_conf="${path_conf}/winapps.conf"

    [ -d "$path_conf" ] || mkdir -p "$path_conf"
    [ -d "${path_share}" ] || mkdir -p "$path_share"
    if [ -f "$file_conf" ]; then
        source "${file_conf}"
    else
        cp "$path_script/../docs/winapps-example.conf" "$file_conf"
        echo "You need to modify $file_conf, exit."
        exit 1
    fi

    if ! command -v xfreerdp >/dev/null; then
        ## try to install the software on Ubuntu
        if sudo apt-get install -y freerdp2-x11; then
            echo "Installed xfreerdp"
        else
            echo "You need xfreerdp!"
            echo "  sudo apt-get install -y freerdp2-x11"
            exit
        fi
    fi

    if [ -f "$path_share/run" ]; then
        last_run=$(stat -t -c %Y "$path_share/run")
        touch "$path_share/run"
        this_run=$(stat -t -c %Y "$path_share/run")
        if ((this_run - last_run < 2)); then
            echo "time is too short!"
            exit 1
        fi
    else
        touch "$path_share/run"
    fi

    RDP_NAME="${RDP_NAME:-RDPWindows}"

    if [ -z "${RDP_IP}" ]; then
        ## try to get the IP from the VM
        if ! groups | grep -q libvirt; then
            echo "You are not a member of the libvirt group. Run the below then reboot."
            echo "  sudo usermod -a -G libvirt \$(whoami)"
            echo "  sudo usermod -a -G kvm \$(whoami)"
            exit 1
        fi
        if ! virsh list | grep -q "${RDP_NAME}"; then
            echo "${RDP_NAME} is not running, run:"
            echo "  virsh start ${RDP_NAME}"
            exit 1
        fi
        RDP_IP=$(virsh net-dhcp-leases default | grep "${RDP_NAME}" | awk '{print $5}')
        RDP_IP=${RDP_IP%%\/*}
    fi

    if [ "${MULTIMON}" = "true" ]; then
        MULTI_FLAG="/multimon"
    else
        MULTI_FLAG="/span"
    fi

    xfreerdp_opt="xfreerdp ${RDP_FLAGS} /d:${RDP_DOMAIN} /u:${RDP_USER} /p:${RDP_PASS} /v:${RDP_IP} -decorations /cert:ignore +auto-reconnect +clipboard +home-drive -wallpaper /scale:${RDP_SCALE:-100} /dynamic-resolution"
    case $1 in
    windows)
        $xfreerdp_opt /wm-class:"Microsoft Windows" >/dev/null 2>&1 &
        ;;
    check)
        $xfreerdp_opt ${MULTI_FLAG} /app:"explorer.exe"
        ;;
    manual)
        $xfreerdp_opt ${MULTI_FLAG} /app:"${2}" >/dev/null 2>&1 &
        ;;
    install)
        _installer "$@"
        ;;
    *)
        if [ -e "${path_script}/../apps/${1}/info" ]; then
            source "${path_script}/../apps/${1}/info"
            ICON="${path_script}/../apps/${1}/icon.svg"
        elif [ -e "$path_share/apps/${1}/info" ]; then
            source "$path_share/apps/${1}/info"
            ICON="$path_share/apps/${1}/icon.svg"
        elif [ -e "/usr/local/share/winapps/apps/${1}/info" ]; then
            source "/usr/local/share/winapps/apps/${1}/info"
            ICON="/usr/local/share/winapps/apps/${1}/icon.svg"
        else
            echo "You need to run \"$0 install\" first."
            exit 1
        fi
        if [ -n "${2}" ]; then
            FILE=$(echo "${2}" | sed 's|'"${HOME}"'|\\\\tsclient\\home|;s|/|\\|g;s|\\|\\\\|g')
            $xfreerdp_opt ${MULTI_FLAG} /wm-class:"${FULL_NAME}" /app:"${WIN_EXECUTABLE}" /app-icon:"${ICON}" /app-cmd:"\"${FILE}\"" >/dev/null 2>&1 &
        else
            $xfreerdp_opt ${MULTI_FLAG} /wm-class:"${FULL_NAME}" /app:"${WIN_EXECUTABLE}" /app-icon:"${ICON}" 1>/dev/null 2>&1 &
        fi
        ;;
    esac
}

main "$@"