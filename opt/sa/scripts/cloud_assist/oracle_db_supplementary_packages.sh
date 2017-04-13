#!/bin/bash

# Install supplementary packages
PKGLIST="unixODBC-devel unixODBC"

/usr/bin/yum -y install $PKGLIST
RETVAL=$?

exit $?
