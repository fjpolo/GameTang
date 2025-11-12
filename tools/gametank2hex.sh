#/usr/bin/bash

if [ "$1" == "" ]; then
    echo "Usage: gametank2hex.sh <x.gametank>"
    exit
fi

HEX="${1/.gametank/.hex}"

hexdump -v -e '/1 "%02x\n"' $1 > $HEX

echo $HEX generated
