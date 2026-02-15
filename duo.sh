
# try:
#     dev.set_configuration()
#     usb.util.claim_interface(dev, WINDEX)
# except usb.core.USBError as e:
#     print(f\"Could not set configuration or claim interface: {str(e)}\")
#     sys.exit(1)

# Send the control transfer
try:
    bmRequestType = 0x21  # Host to Device | Class | Interface
    bRequest = 0x09       # SET_REPORT
    wValue = WVALUE       # 0x035A
    wIndex = WINDEX       # Interface number
    ret = dev.ctrl_transfer(bmRequestType, bRequest, wValue, wIndex, data, timeout=1000)
    if ret != WLENGTH:
        print(f\"Warning: Only {ret} bytes sent out of {WLENGTH}.\")
    else:
        print(\"Data packet sent successfully.\")
except usb.core.USBError as e:
    print(f\"Control transfer failed: {str(e)}\")
    usb.util.release_interface(dev, WINDEX)
    sys.exit(1)

# Release the interface
usb.util.release_interface(dev, WINDEX)
# Reattach the kernel driver if necessary
try:
    dev.attach_kernel_driver(WINDEX)
except usb.core.USBError:
    pass  # Ignore if we can't reattach the driver

sys.exit(0)
" > /tmp/duo/backlight.py
fi

#WIFI_BEFORE=$(nmcli radio wifi)
#BLUETOOTH_BEFORE=$(rfkill -n -o SOFT list bluetooth |head -n1)
KEYBOARD_ATTACHED=false
if [ -n "$(lsusb | grep 'Zenbook Duo Keyboard')" ]; then
    KEYBOARD_ATTACHED=true
fi
MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)

#USED TO ECHO THiS in set status: 
#        BLUETOOTH_BEFORE=${BLUETOOTH_BEFORE}
#        WIFI_BEFORE=${WIFI_BEFORE}

function duo-set-status() {
    echo "
        KEYBOARD_ATTACHED=${KEYBOARD_ATTACHED}
        MONITOR_COUNT=${MONITOR_COUNT}
    " > /tmp/duo/status
}
duo-set-status

function duo-set-kb-backlight() {
    /usr/bin/sudo ${PYTHON3} /tmp/duo/backlight.py ${1} >/dev/null
    echo "${1}" >  /home/shehraan/code/scripts/kb_brightness_level
}

BRIGHTNESS=0
function duo-sync-display-backlight() {
    . /tmp/duo/status
    if [ "${KEYBOARD_ATTACHED}" = false ]; then
        CUR_BRIGHTNESS=$(cat /sys/class/backlight/intel_backlight/brightness)
        if [ "${CUR_BRIGHTNESS}" != "${BRIGHTNESS}" ]; then
            BRIGHTNESS=${CUR_BRIGHTNESS}
            echo "$(date) - DISPLAY - Setting brightness to $(echo ${BRIGHTNESS} |sudo tee /sys/class/backlight/card1-eDP-2-backlight/brightness)"
        fi
    fi
}

function duo-watch-display-backlight() {
    while true; do
        inotifywait -e modify /sys/class/backlight/intel_backlight/brightness >/dev/null 2>&1
        duo-sync-display-backlight
    done
}
: <<'END'
function duo-watch-wifi() {
    while read -r LINE; do
        sleep 1
        . /tmp/duo/status
        if [ "${KEYBOARD_ATTACHED}" = true ]; then
            if [[ "${LINE}" = *"<true>"* ]]; then
                WIFI_BEFORE=enabled
            else
                WIFI_BEFORE=disabled
            fi
            echo "$(date) - NETWORK - WIFI: ${WIFI_BEFORE}"
            duo-set-status
        fi
    done < <(gdbus monitor -y -d org.freedesktop.NetworkManager | grep --line-buffered WirelessEnabled)
}

function duo-watch-bluetooth() {
    while read -r LINE; do
        sleep 1
        . /tmp/duo/status
        if [ "${KEYBOARD_ATTACHED}" = true ]; then
            if [[ "${LINE}" = *"<true>"* ]]; then
                BLUETOOTH_BEFORE=unblocked
            else
                BLUETOOTH_BEFORE=blocked
            fi
            echo "$(date) - NETWORK - Bluetooth: ${BLUETOOTH_BEFORE}"
            duo-set-status
        fi
    done < <(gdbus monitor -y -d org.bluez | grep --line-buffered "'Powered':")
}

function duo-watch-lock() {
    while read -r LINE; do
        sleep 1
        echo "$(date) - DEBUG - ${LINE}"
        . /tmp/duo/status
        if [ "${KEYBOARD_ATTACHED}" = true ]; then
            if [[ "${LINE}" = *"<true>"* ]]; then
                BLUETOOTH_BEFORE=unblocked
            else
                BLUETOOTH_BEFORE=blocked
            fi
            echo "$(date) - NETWORK - Bluetooth: ${BLUETOOTH_BEFORE}"
            duo-set-status
            duo-check-monitor
        fi
    done < <(gdbus monitor -y -d org.freedesktop.login1 | grep --line-buffered "LockedHint")
}
END
function duo-check-monitor() {
    . /tmp/duo/status
    KEYBOARD_ATTACHED=false
    if [ -n "$(lsusb | grep 'Zenbook Duo Keyboard')" ]; then
        KEYBOARD_ATTACHED=true
    fi
    MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)
    duo-set-status

    #Calculate POSITION based on monitor count
    POSITION=0
    if [[ "$MONITOR_COUNT" -ge 3 ]]; then
        POSITION=1920
    fi
#    echo "$(date) - MONITOR - WIFI before: ${WIFI_BEFORE}, Bluetooth before: ${BLUETOOTH_BEFORE}"
#    echo "$(date) - MONITOR - Keyboard attached: ${KEYBOARD_ATTACHED}, Monitor count: ${MONITOR_COUNT}"
    if [ ${KEYBOARD_ATTACHED} = true ]; then
        echo "$(date) - MONITOR - Keyboard attached"
        duo-set-kb-backlight ${DEFAULT_BACKLIGHT}
<< 'END'
	if [ "${WIFI_BEFORE}" = enabled ]; then
            echo "$(date) - MONITOR - Turning on WIFI"
            nmcli radio wifi on
        fi
        if [ "${BLUETOOTH_BEFORE}" = unblocked ]; then
            echo "$(date) - MONITOR - Turning on Bluetooth"
            rfkill unblock bluetooth
        else
            echo "$(date) - MONITOR - Turning off Bluetooth"
            rfkill block bluetooth
        fi
END
        if ((${MONITOR_COUNT} > 1)); then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-2.disable
	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
  --group "Containments" --group "74" --key lastScreen 0
	    plasmashell --replace &
            NEW_MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)
            if ((${NEW_MONITOR_COUNT} == 1)); then
                MESSAGE="Disabled bottom display"
            else
                MESSAGE="ERROR: Bottom display still on"
            fi
            notify-send -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "${MESSAGE}"
        fi
    else
        echo "$(date) - MONITOR - Keyboard detached"

	if (($MONITOR_COUNT == 1 )); then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-2.position.${POSITION},1029 output.eDP-2.rotation.normal

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &

            NEW_MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)
            if [[ "$MONITOR_COUNT" -ge 1 ]]; then
                MESSAGE="Enabled bottom display"
            else
                MESSAGE="ERROR: Bottom display still off"
            fi
            notify-send -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "${MESSAGE}"
	else
	    kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-2.position.${POSITION},1029 output.eDP-2.rotation.normal

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &
            NEW_MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)
            if [[ "$MONITOR_COUNT" -ge 1 ]]; then
                MESSAGE="Enabled bottom display"
            else
                MESSAGE="ERROR: Bottom display still off"
            fi
            notify-send -a "Zenbook Duo" -t 1000 --hint=int:transient:1 -i "preferences-desktop-display" "${MESSAGE}"
    	fi
    fi
}

function duo-watch-monitor() {
    while true; do
#Position based on whether monitors are attached or not. Default is that monitors are not connected
        POSITION=0
	echo "$(date) - MONITOR - Waiting for USB event"
        inotifywait -e attrib /dev/bus/usb/*/ >/dev/null 2>&1

	# Update monitor count BEFORE checking it
        MONITOR_COUNT=$(kscreen-doctor -o | grep "enabled" | wc -l)

    	if [[ "$MONITOR_COUNT" -ge 3 ]]; then
		POSITION=1920
    	fi	    
        duo-check-monitor
    done
}

function duo-cli() {
    . /tmp/duo/status
    if [[ "$MONITOR_COUNT" -ge 3 ]]; then
	    POSITION=1920
    fi	    
    case "${1}" in
    pre|hibernate|shutdown)
        echo "$(date) - ACPI - $@"
        duo-set-kb-backlight 0
    ;;
    post|thaw|boot)
        echo "$(date) - ACPI - $@"
        duo-set-kb-backlight ${DEFAULT_BACKLIGHT}
        duo-check-monitor
    ;;
    kbb)
        echo "$(date) - KEYBOARD - Backlight = ${2}"
        duo-set-kb-backlight ${2}
    ;;
    cycle_kbb)
        CURRENT_LEVEL=$(cat  /home/shehraan/code/scripts/kb_brightness_level 2>/dev/null || echo 0)
        NEXT_LEVEL=$(( (CURRENT_LEVEL + 1) % (MAX_BACKLIGHT + 1) ))
        echo "$(date) - KEYBOARD - Cycling Backlight to ${NEXT_LEVEL}"
        duo-set-kb-backlight ${NEXT_LEVEL}
    ;;
    left-up)
        echo "$(date) - ROTATE - Left-up"
        if [ ${KEYBOARD_ATTACHED} = true ]; then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotation.left
        else
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-1.rotation.left output.eDP-2.position.-1029,0 output.eDP-2.rotation.left

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &

        fi

        ;;
    right-up)
        echo "$(date) - ROTATE - Right-up"
        if [ ${KEYBOARD_ATTACHED} = true ]; then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotate.right
        else
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotate.right output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-2.position.rightof.eDP-1 output.eDP-2.rotate.right

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &

        fi
        ;;
    bottom-up)
        echo "$(date) - ROTATE - Bottom-up"
        if [ ${KEYBOARD_ATTACHED} = true ]; then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotate.8
        else
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotate.8 output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-2.position.above.eDP-1 output.eDP-2.rotate.8

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &

        fi
        ;;
    normal)
        echo "$(date) - ROTATE - Normal"
        if [ ${KEYBOARD_ATTACHED} = true ]; then
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotation.normal output.eDP-2.disable
	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc \
  --group "Containments" --group "74" --key lastScreen 0
	    plasmashell --replace &
        else
            kscreen-doctor output.eDP-1.primary output.eDP-1.scale.${SCALE} output.eDP-1.rotation.normal output.eDP-2.enable output.eDP-2.priority.2 output.eDP-2.scale.${SCALE} output.eDP-2.position.${POSITION},1029 output.eDP-2.rotation.normal output.eDP-1.rotation.normal

	    kwriteconfig6 --file ~/.config/plasma-org.kde.plasma.desktop-appletsrc --group "Containments" --group "74" --key lastScreen 1
	    plasmashell --replace &

        fi
        ;;
    *)
        echo "$(date) - UNKNOWN - $@"
        ;;
    esac
}

function duo-watch-rotate() {
    echo "$(date) - ROTATE - Watching"
    monitor-sensor --accel |
        stdbuf -oL grep "Accelerometer orientation changed:" |
        stdbuf -oL awk '{print $4}' |
        xargs -I '{}' stdbuf -oL "$0" '{}' 2>/dev/null
}

function main() {
    duo-set-kb-backlight ${DEFAULT_BACKLIGHT}
    duo-check-monitor
    duo-watch-monitor &
    duo-watch-rotate &
    duo-watch-display-backlight &
#   duo-watch-wifi &
#   duo-watch-bluetooth
}

if [ -z "${1}" ]; then
    main | tee -a /tmp/duo/duo.log
else
    duo-cli $@ | tee -a /tmp/duo/duo.log
    if [ "${USER}" = root ]; then
        chmod a+w /tmp/duo /tmp/duo/duo.log /tmp/duo/status
    fi
fi

