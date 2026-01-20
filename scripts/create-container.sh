#!/bin/bash
# create an ubuntu docker container, then ssh into it and install specified list of packages
PACKAGES="zsh"
docker run -it --rm ubuntu bash -c "apt-get update && apt-get install -y $PACKAGES" -i
