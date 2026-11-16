#!/bin/bash

echo "Input 1 to list processes, 2 to set process priority."
read choice
if [ $choice == 1 ]; then
    ps -eo ni,pid,comm
fi
if [ $choice == 2 ]; then
    echo "Enter process id: (Run opt. 1 for PID)"
    read pid
    echo "Enter new nice value: (-20 to 19)"
    read nice
    renice -n $nice -p $pid
fi
