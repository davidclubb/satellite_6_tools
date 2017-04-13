#!/bin/bash

#######Oracle DB Disk Layout##########
echo "Writing Disk Layout for Oracle on RHEL6"

# Get information about the local disks for this server
DLIST=`/usr/bin/lsscsi | /bin/awk '{if($2=="disk") print $NF}'`
for D in $DLIST; do
   if [[ -z `grep "^$D" /etc/mtab` ]] && [[ -z $NEXTFREE ]]; then
      NEXTFREE=$D
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

### Disk layout for Oracle DB

#
if [[ -n $NEXTFREE ]]; then

   echo "Writing Common Oracle DB Volumes"

   # Wipe the Disk label
   parted -s $NEXTFREE mklabel msdos

   # Create a PV as the whole volume
   pvcreate -f $NEXTFREE

   # Create the application volume group
   vgcreate -s 4 oraclevg $NEXTFREE


   # f_MakeMount <vg> <lv> <fstype> <mount point> <size> <mode> <owner> <group>

   f_MakeMount oraclevg optoraclelv ext4 /opt/oracle 51200MB 755 oracle oinstall


fi

# NFS Volumes
echo "Writing NFS Configuration"

echo "" >> /etc/fstab
echo "# NFS Volumes" >> /etc/fstab
echo "khoneplzbsv03.acmeplaza.com:/backup/Prod      /sdc_backup     nfs     rw,bg,hard,nointr,rsize=32768,wsize=32768,tcp,vers=3,actimeo=0,timeo=600        0 0" >> /etc/fstab
echo "khonestdbsv01.acmeplaza.com:/backup/ACME    /mdc_backup     nfs     rw,bg,hard,nointr,rsize=32768,wsize=32768,tcp,vers=3,actimeo=0,timeo=600        0 0" >> /etc/fstab
echo 'knenfsmdc001.acmeplaza.com:/oracle_scripts    /misc/scripts   nfs     soft,intr,vers=3,defaults       0 0' >> /etc/fstab
echo 'knenfsmdc001.acmeplaza.com:/oracle_software   /misc/software  nfs     soft,intr,vers=3,defaults       0 0' >> /etc/fstab

# Backup Symlink
echo "Creating Prod vs. Non-Prod Settings"

# Set symlink to /backup according to tier - prod goes to SDC, everything else to MDC
if [[ "`hostname | cut -c9 | tr '[:upper:]' '[:lower:]'`" == "p" ]]; then
   echo 'knenfsmdc001.acmeplaza.com:/oracle_tns_admin_prod /misc/tns_admin     nfs     soft,intr,vers=3,defaults       0 0' >> /etc/fstab
   ln -s /sdc_backup /misc/OraBackup
else
   echo 'knenfsmdc001.acmeplaza.com:/oracle_tns_admin_nonprod /misc/tns_admin  nfs     soft,intr,vers=3,defaults       0 0' >> /etc/fstab
   ln -s /mdc_backup /misc/OraBackup
fi

# Create Mount Points for NFS
for mp in `grep ' nfs ' /etc/fstab | awk '{print $2}'`; do 
   mkdir -p $mp
done

# Mount NFS
/bin/mount -a -t nfs
