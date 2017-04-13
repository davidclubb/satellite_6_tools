#!/bin/bash

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

RELEASE=`f_GetRelease | awk '{print $2}'`


echo "Writing Disk Layout for SAP on RHEL${RELEASE}"

SID=$1
if [[ -z $SID ]]; then
   echo "Error: SID is required."
   exit 4
fi

echo "SID is [$SID]"

# Define Users
SIDADM=`echo $SID | /bin/awk '{print tolower($0)"adm"}'`
ORASID=`echo $SID | /bin/awk '{print "ora"tolower($0)}'`
if [[ -z `getent passwd $ORASID` ]]; then
   #If the "ORASID" user doesn't exist, default to "oracle"
   ORASID=oracle
fi

echo "App Service Account [$SIDADM]"
echo "   `getent passwd $SIDADM`"
echo "DB Service Account  [$ORASID]"
echo "   `getent passwd $ORASID`"

# Get information about the local disks for this server
DLIST=`/usr/bin/lsscsi | /bin/awk '{if($2=="disk") print $NF}'`

echo "Identified the following local disks: [$DLIST]"

echo "DEBUG: The contents of /etc/mtab are:"
cat /etc/mtab
echo ""

echo "DEBUG: The output of pvs is:"
pvs

# For rebuilds, clean up any existing instance of the SAP volume groups
for vg in sapappvg sapdbvg; do

   if [[ -n `vgs | grep $vg` ]]; then
      echo "Found previous version of $vg. It will be removed."
      pvlist=`pvs | grep $vg | awk '{print $1}'`
      vgremove $vg --force
      for pv in $pvlist; do
         echo "Removing LVM metadata from $pv"
         pvremove $pv --force
      done

   fi
done

for D in $DLIST; do
   if [[ -z `grep "^$D" /etc/mtab` ]] && [[ -z `pvs | awk '{print $1}' | grep "^$D"` ]] && [[ -z $SECOND ]]; then
      SECOND=$D
      echo "Identified [$SECOND] as the second disk."
   fi
done


for D in $DLIST; do
   if [[ -z `grep "^$D" /etc/mtab` ]] && [[ -z `pvs | awk '{print $1}' | grep "^$D"` ]] && [[ -z $THIRD ]] && [[ "$D" != "$SECOND" ]]; then
      THIRD=$D
      echo "Identified [$THIRD] as the third disk."
   fi
done


f_MakeMount() {

   VG=$1
   LV=$2
   FSTYPE=$3
   MOUNT_POINT=$4
   SIZE=$5
   MODE=$6
   OWNER=$7
   GROUP=$8
   LDEV=/dev/mapper/${VG}-${LV}

   lvcreate -y -Wy -Zy -n $LV -L $SIZE $VG
   RESULT=$?
   if [[ "$RESULT" == "0" ]]; then
      mkfs -t $FSTYPE $LDEV
      mkdir -p $MOUNT_POINT
      echo -e "${LDEV}\t${MOUNT_POINT}\t\t${FSTYPE}\tdefaults\t1 2" >> /etc/fstab
      mount $MOUNT_POINT
      chmod $MODE $MOUNT_POINT
      chown ${OWNER}:${GROUP} $MOUNT_POINT
   else
      echo "Error creating $LV"
   fi


}

### Disk layout for SAP APP Server

FST=ext4

if [[ "$RELEASE" == "7" ]]; then
   FST=xfs
fi

#
if [[ -n $SECOND ]]; then

   echo "Writing Common APP Server Volumes"

   # Wipe the Disk label
   parted -s $SECOND mklabel msdos

   # Create a PV as the whole volume
   pvcreate -f $SECOND

   # Create the application volume group
   vgcreate -s 4 sapappvg $SECOND


   # f_MakeMount <vg> <lv> <fstype> <mount point> <size> <mode> <owner> <group>

   f_MakeMount sapappvg usrsaplv $FST /usr/sap 20480MB 755 $SIDADM sapsys

   echo "DEBUG: results of /usr/sap"
   echo "  contents of mtab"
   cat /etc/mtab
   echo "  ownership"
   ls -ald /usr/sap

   f_MakeMount sapappvg sapmntlv $FST /sapmnt 10240MB 755 $SIDADM sapsys

else

   echo "No secondary disk identified, nothing to do."


fi

### Disk layout for SAP CI and DB servers

if [[ -n $THIRD ]]; then

echo "Writing CI and DB Volumes"

   # Wipe the Disk label
   parted -s $THIRD mklabel msdos

   # Create a PV as the whole volume
   pvcreate -f $THIRD

   # Create the application volume group
   vgcreate -s 4 sapdbvg $THIRD


   # f_MakeMount <vg> <lv> <fstype> <mount point> <size> <mode> <owner> <group>

   f_MakeMount sapappvg usrsapinterfaceslv $FST /usr/sap/interfaces 5120MB 755 $SIDADM sapsys
   #f_MakeMount sapappvg usrsapmedialv $FST /usr/sap/media 5120MB 777 $SIDADM sapsys
   f_MakeMount sapappvg usrsaptranslv $FST /usr/sap/trans 10240MB 775 $SIDADM sapsys

   f_MakeMount sapdbvg oraclelv $FST /oracle 10240MB 775 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_lv $FST /oracle/${SID} 20480MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_oraarch_lv $FST /oracle/${SID}/oraarch 40960MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_oraflash_lv $FST /oracle/${SID}/oraflash 51200MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_origlogA_lv $FST /oracle/${SID}/origlogA 2048MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_origlogB_lv $FST /oracle/${SID}/origlogB 2048MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_mirrlogA_lv $FST /oracle/${SID}/mirrlogA 1024MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_mirrlogB_lv $FST /oracle/${SID}/mirrlogB 1024MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_sapdata1_lv $FST /oracle/${SID}/sapdata1 10240MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_sapdata2_lv $FST /oracle/${SID}/sapdata2 10240MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_sapdata3_lv $FST /oracle/${SID}/sapdata3 10240MB 755 $ORASID oinstall
   f_MakeMount sapdbvg oracle_${SID}_sapdata4_lv $FST /oracle/${SID}/sapdata4 10240MB 755 $ORASID oinstall




fi

#### Common NFS File Shares ####
echo "Setting up default NFS shares"

mkdir -p /basis
mkdir -p /usr/sap/archive


echo "# NFS" >> /etc/fstab
echo "knenfsmdc001.acmeplaza.com:/basis /basis nfs soft,intr,tcp,bg 0 0" >> /etc/fstab
echo "knenfsmdc001.acmeplaza.com:/sap_archive  /usr/sap/archive  nfs  soft,intr,defaults  0 0" >> /etc/fstab

# If this is a database server make sure to include the /backup mounts
if [[ -n $THIRD ]]; then
   if [[ ! -d /backup_mdc ]]; then mkdir /backup_mdc; fi
   if [[ ! -d /backup_sdc ]]; then mkdir /backup_sdc; fi
   if [[ -L /backup ]]; then /bin/rm /backup; fi

   # Set symlink to /backup according to tier - prod goes to SDC, everything else to MDC
   if [[ "`echo $SID | cut -c3`" == "P" ]]; then
      ln -s /backup_sdc /backup
   else
      ln -s /backup_mdc /backup
   fi

   echo "10.252.132.249:/data/col1/SAP     /backup_mdc   nfs nolock,hard,intr,proto=tcp,noatime,nodiratime,norelatime,rsize=1048576,wsize=1048576 0 0" >> /etc/fstab
   echo "10.252.132.250:/backup            /backup_sdc   nfs nolock,hard,intr,proto=tcp,noatime,nodiratime,norelatime,rsize=1048576,wsize=1048576 0 0" >> /etc/fstab

fi

