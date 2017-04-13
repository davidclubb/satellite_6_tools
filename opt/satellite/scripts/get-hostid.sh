#!/bin/bash

source .sat.env

hammer -u $USER -p $PASS host info --name $1 | grep ^Id: | awk '{print $NF}'
