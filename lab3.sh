#!/bin/bash

# ignore interrupt signals
trap '' TERM
trap '' HUP
trap '' INT

verbose=0

# check for -verbose option
while [ $# -gt 0 ]; do
    case "$1" in
        -verbose)
            verbose=1
            ;;
        *)
            break
            ;;
    esac
    shift
done

# if verbose is on, pass -verbose to configure-host.sh
remoteVerbose=""
if [ $verbose -eq 1 ]; then
    remoteVerbose="-verbose"
    echo "Verbose mode on"
fi

# send to server1-mgmt
# ----------------------

scp configure-host.sh remoteadmin@server1-mgmt:/root 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error: could not copy configure-host.sh to server1-mgmt" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Copied configure-host.sh to server1-mgmt"
    fi
fi

ssh remoteadmin@server1-mgmt -- /root/configure-host.sh -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4 $remoteVerbose
if [ $? -ne 0 ]; then
    echo "Error: configure-host.sh failed on server1-mgmt" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Ran configure-host.sh on server1-mgmt"
    fi
fi

# send to server2-mgmt
# ---------------------

scp configure-host.sh remoteadmin@server2-mgmt:/root 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error: could not copy configure-host.sh to server2-mgmt" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Copied configure-host.sh to server2-mgmt"
    fi
fi

ssh remoteadmin@server2-mgmt -- /root/configure-host.sh -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3 $remoteVerbose
if [ $? -ne 0 ]; then
    echo "Error: configure-host.sh failed on server2-mgmt" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Ran configure-host.sh on server2-mgmt"
    fi
fi

# update local machine host
# ----------------------------

./configure-host.sh -hostentry loghost 192.168.16.3 $remoteVerbose
if [ $? -ne 0 ]; then
    echo "Error: could not update local host entry for loghost" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Updated local hosts entry for loghost"
    fi
fi

./configure-host.sh -hostentry webhost 192.168.16.4 $remoteVerbose
if [ $? -ne 0 ]; then
    echo "Error: could not update local host entry for webhost" >&2
else
    if [ $verbose -eq 1 ]; then
        echo "Updated local hosts entry for webhost"
    fi
fi

