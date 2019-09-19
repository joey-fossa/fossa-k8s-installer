#!/bin/bash

    exec 2>&2 | tee ~/fossa_install.log
    exec 1>&1 | tee ~/fossa_install.log

if [ "$(id -u)" != "0" ]; then
exec sudo "$0" "$@"
fi

        ##Prompt for FOSSA image version
    read -ep "Enter the version tag id: " -i "onprem-2.0.0" tag_id


cd /opt/fossa_helm &>> ~/fossa_install.log
helm upgrade fossa ./fossa/  --set=image.tag=$tag_id &>> ~/fossa_install.log