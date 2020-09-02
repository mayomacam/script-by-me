#!/bin/bash -x
# Bash script to examine the scan results through HTML.
echo "Which type do you get there? "
echo "1. ip-address
2. domain-name"
read -p "option-no.> " op
if [ $op = '1' ]
then
read -p " Enter today target : " ipv
nmap --min-rate 1000 -o /tmp/map.txt $ipv
file="/tmp/map.txt"
ip=$ipv
else
read -p " Enter today target : " ipv
nmap --min-rate 1000 -o /tmp/map.txt $ipv
file="/tmp/map.txt" 
ip=$( cat /tmp/map.txt | grep -e "rDNS" | cut -d ' ' -f 4 | grep -e "^[0-9.]*" | cut -d ':' -f 1 )
fi

echo $ip
echo $file

for p in $( cat $file | grep -e "^[0-9][a-z]*" | cut -d "/" -f 1 ) ;
do
cutycapt --url=$ip:$p --out="/tmp/$ip.$p.png" ;
done

#check if web.html exist
if [ -e /tmp/$ip.html ]
then
rm /tmp/$ip.html;
fi

#making a html file through result

echo "<HTML><BODY><BR>" > /tmp/$ip.html
ls /tmp/*.png
ls /tmp/*.png | awk -F : '{ print $1":\n<BR><IMG SRC=\""$1""$2"\" width=800><BR>"}' >> /tmp/$ip.html
echo "</BODY></HTML>" >> /tmp/$ip.html

#mv web$.html /tmp/web$ipv.html
rm -r /tmp/$ipv
chromium /tmp/$ip.html
