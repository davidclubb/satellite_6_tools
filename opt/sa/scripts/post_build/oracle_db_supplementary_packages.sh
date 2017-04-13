#!/bin/bash

# Install supplementary packages
PKGLIST="unixODBC-devel unixODBC kmod-oracleasm oracleasmlib oracleasm-support"

/usr/bin/yum -y install $PKGLIST
RETVAL=$?

exit $?
