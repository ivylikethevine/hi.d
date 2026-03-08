#!/bin/bash

cd /home/"$USER"/.hi.d/ || exit 1
rm -rf .git
rm .gitignore
rm README.md

# TODO: Modify prompt_colors to anonymize
