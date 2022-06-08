#!/bin/bash
cd /home/oliver/.local/share/Trash/files
while true
do
    TOT1="$(ls -1 | wc -l)"
    sleep 1
    TOT2="$(ls -1 | wc -l)"
    if [ "$TOT1" -gt "$TOT2" ];
    then
        mplayer /home/oliver/音樂/trash.mp3
    fi
done
