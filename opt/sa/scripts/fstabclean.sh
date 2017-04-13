#!/bin/bash

IF=/etc/fstab

# Local filesystems
EXCLSTRING='^#|^$|[[:space:]]nfs[[:space:]]|[[:space:]]cifs[[:space:]]'

# Get width of the longest line in each column
sl1=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $1}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl1 ]]; then sl1=$tsl; fi done
sl2=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $2}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl2 ]]; then sl2=$tsl; fi done
sl3=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $3}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl3 ]]; then sl3=$tsl; fi done
sl4=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $4}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl4 ]]; then sl4=$tsl; fi done
sl5=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $5}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl5 ]]; then sl5=$tsl; fi done
sl6=0
for s in `cat $IF | egrep -v "$EXCLSTRING" | awk '{print $6}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl6 ]]; then sl6=$tsl; fi done

#cat $IF | egrep -v '^#|^$' | awk '{ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s %-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' | egrep -v "[[:space:]]nfs[[:space:]]|[[:space:]]cifs[[:space:]]" | sort -k3

# Print "Other" File Systems
echo "# \"Other\" File Systems"
cat $IF | egrep -v "$EXCLSTRING" | awk '{ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s%-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' | egrep -v "[[:space:]]ext[2,3,4][[:space:]]|[[:space:]]xfs[[:space:]]|[[:space:]]swap[[:space:]]"

echo ""
echo "# Local File Systems"

# Print EXT, XFS
for MP in `egrep "[[:space:]]ext[2,3,4][[:space:]]|[[:space:]]xfs[[:space:]]" $IF | egrep -v "$EXCLSTRING" | awk '{print $2}' | sort`; do
   awk -v mp=$MP '($2 == mp){ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s%-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' $IF
done

# Print SWAP
cat $IF | egrep -v "$EXCLSTRING" | awk '{ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s%-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' | egrep "[[:space:]]swap[[:space:]]"



# Recalculate column widths for NFS
MATCHSTRING='[[:space:]]nfs[[:space:]]'
EXCLSTRING='^#|^$'

if [[ -n `cat $IF | egrep -v "$EXCLSTRING" | egrep "$MATCHSTRING"` ]]; then
   # Get width of the longest line in each column
   sl1=0
   for s in `cat $IF | egrep -v "$EXCLSTRING" | egrep "$MATCHSTRING" | awk '{print $1}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl1 ]]; then sl1=$tsl; fi done
   sl2=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $2}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl2 ]]; then sl2=$tsl; fi done
   sl3=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $3}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl3 ]]; then sl3=$tsl; fi done
   sl4=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $4}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl4 ]]; then sl4=$tsl; fi done
   sl5=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $5}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl5 ]]; then sl5=$tsl; fi done
   sl6=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $6}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl6 ]]; then sl6=$tsl; fi done

   echo ""
   echo "# NFS File Systems"
   cat $IF | egrep -v "$EXCLSTRING" | egrep "$MATCHSTRING" | awk '{ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s%-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' | sort -k2

fi

# Recalculate column widths for CIFS
MATCHSTRING='[[:space:]]cifs[[:space:]]'
EXCLSTRING='^#|^$'

if [[ -n `cat $IF | egrep -v "$EXCLSTRING" | egrep "$MATCHSTRING"` ]]; then

   # Get width of the longest line in each column
   sl1=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $1}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl1 ]]; then sl1=$tsl; fi done
   sl2=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $2}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl2 ]]; then sl2=$tsl; fi done
   sl3=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $3}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl3 ]]; then sl3=$tsl; fi done
   sl4=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $4}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl4 ]]; then sl4=$tsl; fi done
   sl5=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $5}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl5 ]]; then sl5=$tsl; fi done
   sl6=0
   for s in `cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{print $6}'`; do tsl=`echo $s | wc -m`; if [[ $tsl -ge $sl6 ]]; then sl6=$tsl; fi done
   
   echo ""
   echo "# CIFS File Systems"
   cat $IF | egrep -v "$EXCLSTRING"| egrep "$MATCHSTRING" | awk '{ printf "%-'"$sl1"'s %-'"$sl2"'s %-'"$sl3"'s %-'"$sl4"'s %-'"$sl5"'s%-'"$sl6"'s\n", $1,$2,$3,$4,$5,$6 }' | sort -k2

fi

