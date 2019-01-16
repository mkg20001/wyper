#!/bin/bash

cd /srv
if [ -d wyper ]; then
  git -C wyper pull
else
  git clone https://github.com/mkg20001/wyper.git
fi

apt-get install -y jq progress parted

cd wyper

cp -rvp overlay/* /
