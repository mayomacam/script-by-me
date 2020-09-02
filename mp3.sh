#for f in *.opus ; do ffmpeg -i "$f" -acodec libmp3lame -q:a 2 "${f%.*}.mp3"; done
#didn't work as i desire.
# this is the script to convert .opus file to .mp3 using ffmpeg. for other format need codec.
#for i in *.opus; do ffmpeg -i "$i" -f mp3 "${i%}.mp3"; done
#better version
for i in *.wav; do ffmpeg -i "$i" -f mp3 "${i%.*}.mp3"; done
