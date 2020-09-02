#!/bin/bash

read -p "Enter number of line you want to read: " user
line=1
cat /etc/passwd | while read LINE;
do
  echo "$line: $LINE"
  if [ $user -eq $line ]
  then
    break
  fi
  ((line++))
done
