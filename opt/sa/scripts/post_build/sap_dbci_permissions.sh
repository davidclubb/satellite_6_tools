#!/bin/bash
################ORACLE DB FILES AND PERMS#############

# Get Oracle User UID and GID
ORACLEUSER=oracle
ORACLEUSERUID=`/usr/bin/getent passwd $ORACLEUSER | /bin/awk -F':' '{print $3}'`
ORACLEUSERGID=`/usr/bin/getent passwd $ORACLEUSER | /bin/awk -F':' '{print $4}'`

if [[ -n $ORACLEUSERUID ]] && [[ -n $ORACLEUSERGID ]]; then

   for F in /etc/oratab; do
      if [[ ! -f $F ]]; then
         touch $F
      fi
      /bin/chmod 664 $F
      /bin/chown ${ORACLEUSERUID}.${ORACLEUSERGID} $F
   done
fi

