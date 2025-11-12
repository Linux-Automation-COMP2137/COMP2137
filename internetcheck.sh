#!/bin/bash
if ping -c 1 google.com &> /dev/null; then
    echo "Internet is working"
else
    echo "No connection"
fi

