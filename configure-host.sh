#!/bin/bash
# configure-host.sh - simple host configuration script

# ignore TERM, HUP, INT signals
trap '' TERM
trap '' HUP
trap '' INT

verbose=0
desiredName=""
desiredIP=""
hostEntryName=""
hostEntryIP=""

# basic command line processing using case and $1
while [ $# -gt 0 ]; do
    case "$1" in
        -verbose)
            verbose=1
            ;;
        -name)
            shift
            desiredName="$1"
            ;;
        -ip)
            shift
            desiredIP="$1"
            ;;
        -hostentry)
            shift
            hostEntryName="$1"
            shift
            hostEntryIP="$1"
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# ==========================
# handle -name option
# ==========================
if [ -n "$desiredName" ]; then
    currentName=$(hostname)

    if [ "$currentName" = "$desiredName" ]; then
        if [ $verbose -eq 1 ]; then
            echo "Hostname already set to $desiredName"
        fi
    else
        if [ $verbose -eq 1 ]; then
            echo "Changing hostname from $currentName to $desiredName"
        fi

        # write new name into /etc/hostname
        echo "$desiredName" > /etc/hostname 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error: could not update /etc/hostname" >&2
        fi

        # update /etc/hosts - replace old name if it is there
        if grep -q "$currentName" /etc/hosts 2>/dev/null; then
            sed -i "s/$currentName/$desiredName/g" /etc/hosts 2>/dev/null
        else
            # if old name not found, just add a simple line
            echo "127.0.1.1 $desiredName" >> /etc/hosts 2>/dev/null
        fi

        # apply hostname to running system
        hostnamectl set-hostname "$desiredName" 2>/dev/null

        # log the change
        logger -t configure-host -p user.info "Hostname changed from $currentName to $desiredName"
    fi
fi

# ==========================
# handle -ip option
# ==========================
if [ -n "$desiredIP" ]; then
    # guess the lan interface from default route
    laniface=$(ip r | grep default | awk '{print $5}')
    currentIP=""

    if [ -z "$laniface" ]; then
        echo "Error: could not find lan interface from default route" >&2
    else
        # get current IPv4 address on that interface
        currentIP=$(ip -4 a show "$laniface" | grep -w inet | awk '{print $2}' | cut -d/ -f1)

        if [ "$currentIP" = "$desiredIP" ]; then
            if [ $verbose -eq 1 ]; then
                echo "IP address on $laniface already set to $desiredIP"
            fi
        else
            if [ $verbose -eq 1 ]; then
                echo "Changing IP on $laniface from $currentIP to $desiredIP"
            fi

            # update /etc/hosts
            if [ -n "$currentIP" ] && grep -q "$currentIP" /etc/hosts 2>/dev/null; then
                sed -i "s/$currentIP/$desiredIP/g" /etc/hosts 2>/dev/null
            elif ! grep -q "$desiredIP $HOSTNAME" /etc/hosts 2>/dev/null && ! grep -q "$desiredIP $(hostname)" /etc/hosts 2>/dev/null; then
                echo "$desiredIP $(hostname)" >> /etc/hosts 2>/dev/null
            fi

            # very simple netplan update (assumes one file and existing IP)
            netplanFile="/etc/netplan/00-installer-config.yaml"
            if [ -f "$netplanFile" ]; then
                if [ -n "$currentIP" ] && grep -q "$currentIP" "$netplanFile" 2>/dev/null; then
                    sed -i "s/$currentIP/$desiredIP/g" "$netplanFile" 2>/dev/null
                fi
            fi

            # apply IP to the running system
            if [ -n "$laniface" ]; then
                ip addr flush dev "$laniface" 2>/dev/null
                ip addr add "$desiredIP"/24 dev "$laniface" 2>/dev/null
                ip link set "$laniface" up 2>/dev/null
            fi

            # apply netplan config if available
            if command -v netplan >/dev/null 2>&1; then
                netplan apply 2>/dev/null
            fi

            # log the change
            logger -t configure-host -p user.info "IP on $laniface changed from $currentIP to $desiredIP"
        fi
    fi
fi

# ==========================
# handle -hostentry option
# ==========================
if [ -n "$hostEntryName" ] && [ -n "$hostEntryIP" ]; then
    # check if /etc/hosts already has this exact IP+name pair
    if grep -q "$hostEntryIP $hostEntryName" /etc/hosts 2>/dev/null; then
        if [ $verbose -eq 1 ]; then
            echo "/etc/hosts already has entry: $hostEntryIP $hostEntryName"
        fi
    else
        if [ $verbose -eq 1 ]; then
            echo "Updating /etc/hosts entry for $hostEntryName to $hostEntryIP"
        fi

        # remove any existing lines with this name
        if grep -q "$hostEntryName" /etc/hosts 2>/dev/null; then
            sed -i "/$hostEntryName/d" /etc/hosts 2>/dev/null
        fi

        # add the correct IP+name line
        echo "$hostEntryIP $hostEntryName" >> /etc/hosts 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Error: could not update /etc/hosts" >&2
        else
            logger -t configure-host -p user.info "Updated host entry: $hostEntryIP $hostEntryName"
        fi
    fi
fi

