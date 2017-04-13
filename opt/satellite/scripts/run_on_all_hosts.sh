#!/bin/bash


COMMAND=$@

cd /opt/satellite/scripts

HAMMER=./hammer.sh
SSHU=root
PKEY=/usr/share/foreman-proxy/.ssh/id_rsa_foreman_proxy
SSHCOM="/bin/ssh -q -o Batchmode=yes -o stricthostkeychecking=no -o userknownhostsfile=/dev/null"




for HIP in `$HAMMER host list | awk -F '|' '{print $2","$5}' | grep '^ ' | tr -d ' ' | grep -v "^NAME,"`; do

   HN=$(echo $HIP | awk -F',' '{print $1}')
   IP=$(echo $HIP | awk -F',' '{print $2}')

   if [[ -n `nmap $IP -p 22 | grep ^22 | grep open` ]]; then

      $SSHCOM -i $PKEY $SSHU@$IP "$COMMAND" 2>&1 | sed "s/^/$HN : /g" &

   else

      echo "$HN : NOT CONNECTABLE"

   fi

     


done

