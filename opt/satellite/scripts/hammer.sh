#!/bin/bash

source /opt/satellite/scripts/.sat.env

hammer -u $USER -p $PASS $@
