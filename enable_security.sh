#!/bin/bash
############################################################
##This script enables the FOSSA vulnerabilities features ###
############################################################
#Update FOSSA db
kubectl -n fossa exec -it database-0 -- bash -c "psql -d fossa -U fossa -c 'UPDATE \"Organizations\" SET "security_enabled" = true;'"

#Get name of core container
set -f -- $(kubectl -n fossa get pod | grep core)

#Seed the security database
kubectl -n fossa exec -it $1 -- bash -c "/fossa/tsnode /fossa/tools/fossa sequelize db:seed:all"
