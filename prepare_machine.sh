#!/bin/bash

cd /srv
if [ -d wyper ]; then
  git -C wyper pull
else
  git clone https://github.com/mkg20001/wyper.git
fi

apt-get install -y jq progress parted smartmontools --no-install-recommends

cd wyper

cp -rvp overlay/* /

update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/wyper/wyper.plymouth 100
update-alternatives --install /usr/share/plymouth/themes/default.grub default.grub /usr/share/plymouth/themes/wyper/wyper.grub 100
update-alternatives --install /usr/share/plymouth/themes/text.plymouth text.plymouth /usr/share/plymouth/themes/wyper-text/wyper-text.plymouth 100
update-initramfs -u
