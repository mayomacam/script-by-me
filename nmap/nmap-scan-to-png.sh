#!/bin/bash


for ip in $(cat nmap-nmap-123 | grep 80 | grep -v "Nmap" | awk '{print $2}'); do cutycapt --url=$ip --out=$ip.png;done
