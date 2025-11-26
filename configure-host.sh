#!/bin/bash

# don't react to TERM, HUP, or INT signals
trap '' TERM
trap '' HUP
trap '' INT

verbose=0
newHostName=""
newIp=""
hostEntryName=""
hostIP=""

# handle basic command-line options with case and $1
while [ $# -gt 0 ]; do
    case "$1" in
        -verbose)
            verbose=1
            ;;
        -name)
            shift
            newHostName="$1"
            ;;
        -ip)
            shift
            newIp="$1"
            ;;
        -hostentry)
            shift
            hostEntryName="$1"
            shift
            hostIP="$1"
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# handle -name option
# --------------------
if [ -n "$newHostName" ]; then
    currentName=$(hostname)

    if [ "$currentName" = "$newHostName" ]; then
        if [ $verbose -eq 1 ]; then
            echo "Hostname already set to $newHostName"
        fi
    else
        if [ $verbose -eq 1 ]; then
            echo "Changing hostname from $currentName to $newHostName"
        fi

        # saves the updated name into /etc/hostname
        echo "$newHostName" > /etc/hostname 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error: could not update /etc/hostname" >&2
        fi

        # check /etc/hosts and update the name if the old one shows up
        if grep -q "$currentName" /etc/hosts 2>/dev/null; then
            sed -i "s/$currentName/$newHostName/g" /etc/hosts 2>/dev/null
        else
            # if the old name doesnt show up just add a simple line
            echo "127.0.1.1 $newHostName" >> /etc/hosts 2>/dev/null
        fi

        # apply the new hostname to the running system
        hostnamectl set-hostname "$newHostName" 2>/dev/null

        # records this change in the logs
        logger -t configure-host -p user.info "Hostname changed from $currentName to $newHostName"
    fi
fi

# handle -ip option
# ------------------
if [ -n "$newIp" ]; then
    # figure out the LAN interface from the default route
    laniface=$(ip r | grep default | awk '{print $5}')
    currentIP=""

    if [ -z "$laniface" ]; then
        echo "Error: could not find lan interface from default route" >&2
    else
        # check what IPv4 address that interface is using
        currentIP=$(ip -4 a show "$laniface" | grep -w inet | awk '{print $2}' | cut -d/ -f1)

        if [ "$currentIP" = "$newIp" ]; then
            if [ $verbose -eq 1 ]; then
                echo "IP address on $laniface already set to $newIp"
            fi
        else
            if [ $verbose -eq 1 ]; then
                echo "Changing IP on $laniface from $currentIP to $newIp"
            fi

            # update /etc/hosts
            if [ -n "$currentIP" ] && grep -q "$currentIP" /etc/hosts 2>/dev/null; then
                sed -i "s/$currentIP/$newIp/g" /etc/hosts 2>/dev/null
            elif ! grep -q "$newIp $HOSTNAME" /etc/hosts 2>/dev/null && ! grep -q "$newIp $(hostname)" /etc/hosts 2>/dev/null; then
                echo "$newIp $(hostname)" >> /etc/hosts 2>/dev/null
            fi

             # basic netplan change, assuming one YAML file and a set IP
            netplanFile=$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)
            if [ -n "$netplanFile" ] && [ -f "$netplanFile" ]; then
                if [ -n "$currentIP" ] && grep -q "$currentIP" "$netplanFile" 2>/dev/null; then
                    sed -i "s/$currentIP/$newIp/g" "$netplanFile" 2>/dev/null
                fi
            fi

            # apply IP to the running system
            if [ -n "$laniface" ]; then
                ip addr flush dev "$laniface" 2>/dev/null
                ip addr add "$newIp"/24 dev "$laniface" 2>/dev/null
                ip link set "$laniface" up 2>/dev/null
            fi

            # run netplan apply if a config file is available
            if command -v netplan >/dev/null 2>&1; then
                netplan apply 2>/dev/null
            fi

            # record the change in the logs
            logger -t configure-host -p user.info "IP on $laniface changed from $currentIP to $newIp"
        fi
    fi
fi

# handle -hostentry option
# -------------------------
if [ -n "$hostEntryName" ] && [ -n "$hostIP" ]; then
    # confirm whether /etc/hosts already contains this IP and hostname
    if grep -q "$hostIP $hostEntryName" /etc/hosts 2>/dev/null; then
        if [ $verbose -eq 1 ]; then
            echo "/etc/hosts already has entry: $hostIP $hostEntryName"
        fi
    else
        if [ $verbose -eq 1 ]; then
            echo "Updating /etc/hosts entry for $hostEntryName to $hostIP"
        fi

        # remove any existing lines with this name
        if grep -q "$hostEntryName" /etc/hosts 2>/dev/null; then
            sed -i "/$hostEntryName/d" /etc/hosts 2>/dev/null
        fi

        # add the correct IP and name line
        echo "$hostIP $hostEntryName" >> /etc/hosts 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error: could not update /etc/hosts" >&2
        else
            logger -t configure-host -p user.info "Updated host entry: $hostIP $hostEntryName"
        fi
    fi
fi

