#!/bin/bash

echo "Writing Disk Layout for SAP on RHEL6"

SID=$1

# Define Users
SIDADM=`echo $SID | /bin/awk '{print tolower($0)"adm"}'`
ORASID=`echo $SID | /bin/awk '{print "ora"tolower($0)}'`
if [[ -z `getent passwd $ORASID` ]]; then
   #If the "ORASID" user doesn't exist, default to "oracle"
   ORASID=oracle
fi

# Get information about the local disks for this server
DLIST=`/usr/bin/lsscsi | /bin/awk '{if($2=="disk") print $NF}'`

# Get information about the local disks for this server
DLIST=`/usr/bin/lsscsi | /bin/awk '{if($2=="disk") print $NF}'`
for D in $DLIST; do
   if [[ -z `grep "^$D" /etc/mtab` ]] && [[ -z `pvs | awk '{print $1}' | grep "^$D"` ]] && [[ -z $SECOND ]]; then
      SECOND=$D
   fi
done

for D in $DLIST; do
   if [[ -z `grep "^$D" /etc/mtab` ]] && [[ -z `pvs | awk '{print $1}' | grep "^$D"` ]] && [[ -z $THIRD ]] && [[ "$D" != "$SECOND" ]]; then
      THIRD=$D
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

   lvcreate -n $LV -L $SIZE $VG
   mkfs -t $FSTYPE $LDEV
   mkdir -p $MOUNT_POINT
   echo -e "${LDEV}\t${MOUNT_POINT}\t\t${FSTYPE}\tdefaults\t1 2" >> /etc/fstab
   mount $MOUNT_POINT
   chmod $MODE $MOUNT_POINT
   chown ${OWNER}:${GROUP} $MOUNT_POINT


}

### Disk layout for SAP APP Server

#
if [[ -n $SECOND ]]; then

   echo "Writing Common APP Server Volumes"

   # Wipe the Disk label
   parted -s $SECOND mklabel msdos

   # Create a PV as the whole volume
   pvcreate $SECOND

   # Create the application volume group
   vgcreate -s 4 sapappvg $SECOND


   # f_MakeMount <vg> <lv> <fstype> <mount point> <size> <mode> <owner> <group>

   f_MakeMount sapappvg usrsaplv ext4 /usr/sap 15360MB 755 $SIDADM sapsys
   f_MakeMount sapappvg sapmntlv ext4 /sapmnt 2660MB 755 $SIDADM sapsys


fi

### Disk layout for SAP CI and DB servers

if [[ -n $THIRD ]]; then

echo "Writing CI and DB Volumes"

   # Wipe the Disk label
   parted -s $THIRD mklabel msdos

   # Create a PV as the whole volume
   pvcreate $THIRD

   # Create the application volume group
   vgcreate -s 4 sapdbvg $THIRD


   # f_MakeMount <vg> <lv> <fstype> <mount point> <size> <mode> <owner> <group>

   f_MakeMount sapappvg usrsapinterfaceslv ext4 /usr/sap/interfaces 5120MB 755 $SIDADM sapsys
   f_MakeMount sapappvg usrsapmedialv ext4 /usr/sap/media 5120MB 777 $SIDADM sapsys
   f_MakeMount sapappvg usrsaptranslv ext4 /usr/sap/trans 10240MB 775 $SIDADM sapsys

   f_MakeMount sapdbvg oraclelv ext4 /oracle 10240MB 775 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_lv ext4 /oracle/${SID} 20480MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_oraarch_lv ext4 /oracle/${SID}/oraarch 40960MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_origlogA_lv ext4 /oracle/${SID}/origlogA 2048MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_origlogB_lv ext4 /oracle/${SID}/origlogB 2048MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_mirrlogA_lv ext4 /oracle/${SID}/mirrlogA 500MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_mirrlogB_lv ext4 /oracle/${SID}/mirrlogB 500MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_sapdata1_lv ext4 /oracle/${SID}/sapdata1 10240MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_sapdata2_lv ext4 /oracle/${SID}/sapdata2 10240MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_sapdata3_lv ext4 /oracle/${SID}/sapdata3 10240MB 755 $ORASID dba
   f_MakeMount sapdbvg oracle_${SID}_sapdata4_lv ext4 /oracle/${SID}/sapdata4 10240MB 755 $ORASID dba




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

   echo "10.252.132.249:/data/col1/SAP     /backup_mdc   nfs hard,intr,proto=tcp,noatime,nodiratime,norelatime,rsize=1048576,wsize=1048576 0 0" >> /etc/fstab
   echo "10.252.132.250:/backup            /backup_sdc   nfs hard,intr,proto=tcp,noatime,nodiratime,norelatime,rsize=1048576,wsize=1048576 0 0" >> /etc/fstab

fi

