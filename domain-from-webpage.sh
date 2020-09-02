grep "href=" index.html | grep "\.megacorpone" | grep -v "www\.megacorpone\.com" | awk -F "http://" '{print $2}' | cut -d "/" -f 1

#give domainnames from webpage
#or can use
#grep -o '[^/]*\.megacorpone\.com' index.html | sort - u > list.txt
