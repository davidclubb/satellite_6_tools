#!/bin/bash
echo $1 >/tmp/test.output
echo "first arg" $1
echo "everything else" ${@:2}
