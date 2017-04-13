#!/bin/bash

# Install supplementary packages
PKGGRPLIST="groupinstall compat-libraries debugging directory-client hardware-monitoring large-systems network-file-system-client performance perl-runtime x11"

PKGLIST="SAPHostAgent autoconf automake compat-openldap cyrus-sasl-lib.i686 expat.i686 fontconfig.i686 freetype.i686 glibc.i686 keyutils-libs.i686 krb5-libs.i686 libcom_err.i686 libidn-devel libidn-devel.i686 libidn.i686 libselinux.i686 libssh2.i686 libX11.i686 libXau.i686 libxcb.i686 nspr.i686 nss.i686 nss-softokn-freebl.i686 nss-softokn.i686 nss-util.i686 openldap.i686 openssl.i686 scx transfig unixODBC unixODBC-devel uuidd"

/usr/bin/yum -y groupinstall $PKGGRPLIST
RETVAL=$?

if [[ "$RETVAL" == "0" ]]; then
   /usr/bin/yum -y install $PKGLIST
   RETVAL=$?
fi

exit $RETVAL
