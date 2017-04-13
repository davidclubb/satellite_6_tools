#!/bin/bash

# Verify the system is a database

if [[ -n `grep '/oracle' /etc/mtab | egrep 'sapdata|oraarch|origlog'` ]]; then

   if [[ -z `getent group oinstall` ]]; then

      groupadd -g 500 oinstall

   fi

   if [[ -z `getent passwd oracle` ]]; then
      useradd -u 500 -g oinstall -G dba,oper,sapinst -c "Oracle Service Account" -m -d /usr/local/home/oracle oracle
   fi

   id oracle

else
   echo "`hostname` does not appear to have an Oracle DB"

fi

