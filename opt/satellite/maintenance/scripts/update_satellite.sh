#!/bin/bash

/usr/bin/katello-service stop
/usr/bin/yum -y upgrade

/sbin/satellite-installer --scenario satellite --upgrade

/sbin/reboot
