#!/bin/bash -x

#z(){
#  echo $1
 # zip2john $1 > hash.txt
 # }
  
main(){
  while true;
  do
    var=$(ls | grep -e '[0-9]*.zip')
    echo $var;
    #z < $v
    $(zip2john $var > hash.txt)
    $(john --format=PKZIP hash.txt /usr/share/wordlists/rockyou.txt )
    #pass=$(cat hash.txt | grep -e '^[[:digit:]]')
    $(john --show hash.txt > b.txt)
    pass=$(cat b.txt | cut -d ':' -f 2 | grep -e '^[[:digit:]]*$')
    $(7z x $var -p$pass)
    $(cp $var ./z/)
    $(rm $var)
  done
  }
 
main
