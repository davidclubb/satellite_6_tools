#!/bin/bash

# Install VMTools from the satellite

IMGSRVIP=10.252.14.5

if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
   echo "`$VTS`:$0 Beginning VMWare Tools Installation." | $LOG1
fi
echo "Beginning VMWare Tools Installation."

if [[ -n `uname -r | grep '\.el7\.'` ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Detected RHEL 7 - native open-vmtools will be used instead per VMWare's Recommendation." | $LOG1
   fi
   echo "Detected RHEL 7 - native open-vmtools will be used instead per VMWare's Recommendation."
   exit
fi

# Check to see if VMware-tools is already installed
VMTM=/etc/vmware-tools/manifest.txt.shipped
if [[ -s $VMTM ]]; then
   INSTALLED_VERSION=`grep "^vmtoolsd.version" $VMTM | awk -F '"' '{print $2}'`
   if [[ -n `echo $1 | egrep -i "^-r$"` ]]; then
   
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 VMTools version $INSTALLED_VERSION will be uninstalled." | $LOG1
      fi
      echo "VMTools version $INSTALLED_VERSION will be uninstalled and replaced with the current version."
      /etc/vmware-tools/installer.sh uninstall

   else

      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 VMTools version $INSTALLED_VERSION is already installed. Use /etc/vmware-tools/installer.sh uninstall if you wish to re-install." | $LOG1
      fi
      echo "VMTools version $INSTALLED_VERSION is already installed. Use /etc/vmware-tools/installer.sh uninstall if you wish to re-install."
      exit 0
   fi
else
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 VMTools will be installed." | $LOG1
   fi
   echo "VMTools will be installed."

fi
BASEURL="http://${IMGSRVIP}/hw_tools/VMWare"
#LOCALDIR=/var/satellite/post_scripts/hw_tools/VMWare
LOCALDIR=/opt/sa/hw_tools/VMWare
if [[ ! -d "$LOCALDIR" ]]; then mkdir -p "$LOCALDIR"; fi

# Get version information from the server
REMOTEVER=`wget -q ${BASEURL}/current.txt -O - | grep -i VERSION | awk -F'=' '{print $2}'`
LOCALVER=`grep -i ^VERSION "${LOCALDIR}/current.txt" 2>&1 | grep -v "No such" | awk -F'=' '{print $2}'`
if [[ -z $LOCALVER ]] && [[ -z $REMOTEVER ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Fatal Error: unable to get version information for VMTools" | $LOG1
   fi
   echo "Fatal Error: unable to get version information for VMTools"
   exit 15
fi

# See if we need to download a new copy from the image server
if [[ -n $REMOTEVER ]] && [[ "$LOCALVER" != "$REMOTEVER" ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Detected different version of VMTools on image server, downloading..." | $LOG1
   fi
   echo "Detected different version of VMTools on image server, downloading..."
   wget --progress=bar:force "${BASEURL}/${REMOTEVER}" -O "${LOCALDIR}/${REMOTEVER}" 

   # If we successfully downloaded a new copy then make that the version we'll attempt to install
   if [[ -s "${LOCALDIR}/${REMOTEVER}" ]]; then
      LOCALVER=$REMOTEVER
      echo "VERSION=${LOCALVER}" > "${LOCALDIR}/current.txt"
   fi

fi

# Unpack and install
# Read the top of the tarred directory structure so we know where it will unpack
VMTOOLS_TARBALL="${LOCALDIR}/${LOCALVER}"
VMTOOLS_INSTLOG=/var/log/install/vmtools_install.log
TOPDIR=`tar -tzf $VMTOOLS_TARBALL 2>&1 | head -1 | tr -d '/' | awk '{print $1}'`
mkdir -p /var/log/install

# Extracting Tarball
tar -xzf $VMTOOLS_TARBALL -C /tmp

if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
   echo "`$VTS`:$0 Starting VMTools install - logs will be written to $VMTOOLS_INSTLOG" | $LOG1
fi
echo "Starting VMTools install - logs will be written to $VMTOOLS_INSTLOG"

# Running installer
#/tmp/${TOPDIR}/vmware-install.pl --default EULA_AGREED=yes 2>&1 >> $VMTOOLS_INSTLOG
/tmp/${TOPDIR}/vmware-install.pl --default EULA_AGREED=yes >> $VMTOOLS_INSTLOG 2>&1
RESULT=$?

if [[ $RESULT != 0 ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Failure: VMTools installer exited with non-zero code [$RESULT] see log for details" | $LOG1
   fi
   echo "Failure: VMTools installer exited with non-zero code [$RESULT] see log for details"
else
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 VMTools installation succeeded." | $LOG1
   fi
   echo "VMTools installation succeeded."

   # Set time based on Host
   #/usr/bin/vmware-toolbox-cmd timesync enable

   # Make sure NTP is off
   #if [[ -s /etc/init.d/ntpd ]]; then /sbin/chkconfig ntpd off; fi
   #if [[ -n `ps --no-header -C ntpd -o pid` ]]; then
   #   /etc/init.d/ntpd stop
   #fi
fi

if [[ -f /etc/init.d/vmware-tools ]]; then
   sed -i 's/\/usr\/bin\/tpvmlpd/#\/usr\/bin\/tpvmlpd/g' /etc/init.d/vmware-tools
fi

# Remove the script from rc.local if needed
sed -i "/`basename $0`/d" /etc/rc.d/rc.local
sed -i "/setup_vmtools.sh/d" /etc/rc.d/rc.local
