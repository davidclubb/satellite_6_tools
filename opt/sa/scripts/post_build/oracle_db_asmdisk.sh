#!/bin/bash

# Make sure ASM is running
/etc/init.d/oracleasm restart

ASM=/usr/sbin/oracleasm
PARTED=/sbin/parted
PARTPROBE=/sbin/partprobe

# Clear any previously existing ASM disk labels and remove the partition from the disk
for PASMD in `$ASM listdisks`; do
   echo "Removing previous version of [$PASMD]"
   DEV=$( $ASM querydisk -p $PASMD | grep '/dev/' | awk -F':' '{print $1}' | tr -d '[0-9]' )
   $ASM deletedisk $PASMD
   $PARTED -s $DEV mklabel gpt
done

# Free disks count
FC=0
DN=0

# List all the SCSI type disks found
for d in `ls /sys/block | grep ^sd`; do
   echo "Checking [$d] to see if it's in use."
   FREE=YES

   # If disk is partitioned it isn't free
   if [[ -n `ls /sys/block/$d | grep ^sd` ]]; then
      echo "   [$d] is partitioned."
      
      # Check each partition to see if it's labeled for ASM
      for PT in `ls /sys/block/$d | grep ^sd`; do
         echo "   Checking [$PT]"
         LBL=$(dd if=/dev/${PT} bs=1 count=4096 skip=16 2> /dev/null)
         if [[ -n `echo $LBL | grep ^ORCLDISK` ]]; then
            ASMD=$(echo $LBL | sed 's/^ORCLDISK//')
            echo "   [$PT] is labeled for ASM as [$ASMD]"
            if [[ -n `echo $ASMD | egrep '^FLASH|^DATA'` ]]; then
               echo "      [$ASMD] will be cleared and [$d] will be wiped"
               $ASM deletedisk $ASMD
            else
               FREE=NO   
            fi
         else
            FREE=NO   
         fi


      done      

   fi

   # If the disk has an LVM label it isn't free
   if [[ -n `/sbin/pvs --noheadings | awk '{print $1}' | awk -F'/' '{print $3}' | tr -d '[0-9]' | grep $d` ]]; then
      echo "   [$d] has an LVM label."
      FREE=NO
   fi

   if [[ $FREE == YES ]]; then
      echo "   [$d] is not in use"
      let FC=$FC+1

      # The first disk will be labeled as FLASH01
      if [[ $FC -eq 1 ]]; then
         echo "   Configuring [$d] in ASM as FLASH01"
         $PARTED -s /dev/${d} mklabel gpt mkpart primary -a optimal "1 -1"
         $PARTPROBE
         sleep 1
         $ASM createdisk FLASH01 /dev/${d}1
      elif [[ $FC -gt 1 ]] && [[ $FC -lt 10 ]]; then
         let DN=$DN+1
         PDN=$(printf "%02d" $DN)
         echo "   Configuring [$d] in ASM as DATA${PDN}"
         $PARTED -s /dev/${d} mklabel gpt mkpart primary -a optimal "1 -1"
         $PARTPROBE
         sleep 1
         $ASM createdisk DATA${PDN} /dev/${d}1
      fi
   fi
done

