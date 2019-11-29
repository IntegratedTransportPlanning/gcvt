#!/bin/bash

# cd to directory of script, obviously
cd "${0%/*}"

# Docker won't let this be a symlink
mkdir -p data
cp -r ../../data/sensitive/GCVT_Scenario_Pack/* data
