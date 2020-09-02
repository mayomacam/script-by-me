#!/bin/bash

line=1
cat /etc/passwd | while read LINE;
do
  echo "$line: $LINE"
  ((line++))
done
