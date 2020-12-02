#!/bin/sh

cookiefile=./cookie.txt

if [ $# -eq 1 ]; then
  channel=$1
  output=./$1.aac
elif [ $# -eq 2 ]; then
  channel=$1
  output=$2
elif [ $# -eq 4 ]; then
  channel=$1
  output=$2
  mail=$3
  pass=$4
else
  echo "usage : $0 channel_name [outputfile] [mail] [pass]"
  exit 1
fi

###
# radiko premium
###
if [ $mail ]; then
  wget -q --save-cookie=$cookiefile \
       --keep-session-cookies \
       --post-data="mail=$mail&pass=$pass" \
       https://radiko.jp/ap/member/login/login

  if [ ! -f $cookiefile ]; then
    echo "failed login"
    exit 1
  fi
fi

#
# get player
#
wget -q -N --no-if-modified-since http://radiko.jp/apps/js/playerCommon.js

if [ $? -ne 0 ]; then
  echo "failed get player"
  exit 1
fi

#
# get keydata
#
playerargs=`sed -n 's/.*new RadikoJSPlayer(\(.*\)/\1/p' ./playerCommon.js | sed 's/, /\n/g'`
appid=`echo "$playerargs" | sed -n 2p | sed -e "s/^'//" -e "s/'$//"`
authkey=`echo "$playerargs" | sed -n 3p | sed -e "s/^'//" -e "s/'$//"`

if [ x = x"$authkey" ]; then
  echo "failed get keydata"
  exit 1
fi

if [ -f auth1 ]; then
  rm -f auth1
fi

#
# access auth1
#
wget -q \
     --header="X-Radiko-App: ${appid}" \
     --header="X-Radiko-App-Version: 0.0.1" \
     --header="X-Radiko-User: dummy_user" \
     --header="X-Radiko-Device: pc" \
     --no-check-certificate \
     --load-cookies $cookiefile \
     --save-headers \
     https://radiko.jp/v2/api/auth1

if [ $? -ne 0 ]; then
  echo "failed auth1 process"
  exit 1
fi

#
# get partial key
#
authtoken=`perl -ne 'print $1 if(/x-radiko-authtoken: ([\w-]+)/i)' auth1`
offset=`perl -ne 'print $1 if(/x-radiko-keyoffset: (\d+)/i)' auth1`
length=`perl -ne 'print $1 if(/x-radiko-keylength: (\d+)/i)' auth1`

partialkey=`echo -n "${authkey}" | dd bs=1 skip=${offset} count=${length} 2> /dev/null | base64`

echo "authtoken: ${authtoken} \noffset: ${offset} length: ${length} \npartialkey: $partialkey"

rm -f auth1

if [ -f auth2 ]; then
  rm -f auth2
fi

#
# access auth2
#
wget -q \
     --header="X-Radiko-AuthToken: ${authtoken}" \
     --header="X-Radiko-PartialKey: ${partialkey}" \
     --header="X-Radiko-User: dummy_user" \
     --header="X-Radiko-Device: pc" \
     --load-cookies $cookiefile \
     --no-check-certificate \
     https://radiko.jp/v2/api/auth2

if [ $? -ne 0 -o ! -f auth2 ]; then
  echo "failed auth2 process"
  exit 1
fi

echo "authentication success"

areaid=`perl -ne 'print $1 if(/^([^,]+),/i)' auth2`
echo "areaid: $areaid"

rm -f auth2

#
# get playlist-url
#

if [ -f ${channel}.xml ]; then
  rm -f ${channel}.xml
fi

wget -q "http://radiko.jp/v3/station/stream/${appid}/${channel}.xml"

if [ x != x"$ft" ]; then
  timefree=1
else
  timefree=0
fi
if [ -f $cookiefile ]; then
  areafree=1
else
  areafree=0
fi
lsid=`date +%s999 -d '999999 seconds' | tr -d '\n' | md5sum | cut -d ' ' -f 1`
playlist_urls=`echo "cat //url[@timefree='${timefree}'][@areafree='${areafree}']/playlist_create_url/text()" | xmllint -shell ${channel}.xml | grep ://`
playlist_url=`echo "$playlist_urls" | head -1`
#playlist_url=`echo "$playlist_urls" | grep -v tf-rpaa.smartstream.ne.jp | head -1`

if [ $areafree = 0 ]; then
  connectiontype='b'
else
  connectiontype='c'
fi
if [ $timefree = 0 ]; then
  playlist_param="station_id=${channel}&l=15&lsid=${lsid}&type=${connectiontype}"
else
  playlist_param="station_id=${channel}&start_at=${ft}&ft=${ft}&end_at=${to}&to=${to}&l=15&lsid=${lsid}&type=${connectiontype}"
fi

if echo "$playlist_url" | grep -q -F '?'; then
  playlist_url="${playlist_url}&${playlist_param}"
else
  playlist_url="${playlist_url}?${playlist_param}"
fi

rm -f ${channel}.xml

#
# ffmpeg
#
cp -i /dev/null "$output"
ffmpeg -nostdin \
       -headers "X-Radiko-AuthToken: ${authtoken}" \
       -i "$playlist_url" \
       -c copy -f adts pipe: > "$output"
#       -c copy "$output"
