#!/bin/bash

cd /home/"$USER"/.sshrc.d/ || exit 1
rm -rf .git
rm -rf reports
rm .gitignore
rm README.md
