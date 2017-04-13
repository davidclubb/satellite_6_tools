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

if [[ "$RELEASE" == "6" ]]; then

   # Install supplementary groups
   PKGGRPLIST="compat-libraries debugging directory-client hardware-monitoring large-systems network-file-system-client performance perl-runtime x11"

   PKGLIST="SAPHostAgent autoconf automake compat-openldap cyrus-sasl-lib.i686 expat.i686 fontconfig.i686 freetype.i686 glibc.i686 keyutils-libs.i686 krb5-libs.i686 libcom_err.i686 libidn-devel libidn-devel.i686 libidn.i686 libselinux.i686 libssh2.i686 libX11.i686 libXau.i686 libxcb.i686 nspr.i686 nss.i686 nss-softokn-freebl.i686 nss-softokn.i686 nss-util.i686 openldap.i686 openssl.i686 scx transfig unixODBC unixODBC-devel uuidd"

elif [[ "$RELEASE" == "7" ]]; then

   PKGGRPLIST="compat-libraries large-systems network-file-system-client performance"

   PKGLIST="SAPHostAgent uuidd compat-libstdc++-33"

else
   echo "Unsppported platform [`f_GetRelease`]"
   exit 2
fi

/usr/bin/yum -y groupinstall $PKGGRPLIST
RETVAL=$?

if [[ "$RETVAL" == "0" ]]; then
   /usr/bin/yum -y install $PKGLIST
   RETVAL=$?
fi

exit $RETVAL
