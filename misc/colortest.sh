#! /bin/bash

echo "Foregrounds (X is 0 to 255): ESC [ 38 ; 5 ; X m" 
echo " where X is 0 to 255" 
for i in {0..15}; do 
    for j in {0..15}; do 
        let "x = i * 16 + j" 
        echo -en "\033[38;5;${x}m ${x}\033[0m" 
    done 
    echo 
done

echo "Backgrounds (X is 0 to 255): ESC [ 48 ; 5 ; X m" 
for i in {0..15}; do 
    for j in {0..15}; do 
        let "x = i * 16 + j" 
        echo -en "\033[48;5;${x}m ${x}\033[0m" 
    done 
    echo 
done
