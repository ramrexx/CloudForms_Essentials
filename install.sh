#!/bin/sh

if [ ! -e /var/www/miq/vmdb/config/database.yml ]; then
	echo "Please configure CFME through appliance_console."
	sleep 3
	appliance_console
	if [ ! -e /var/www/miq/vmdb/config/database.yml ]; then
		echo "database still not configured. Exiting"
		exit 1
	fi
fi

git clone https://github.com/rhtconsulting/cfme-rhconsulting-scripts.git

FAIL=0
MAXFAIL=60

#I'm open to suggestions on a better way to see if things are actually up.
while [ $(curl -k -u admin:smartvm https://127.0.0.1/api/ -w "%{http_code}" -o /dev/null 2>/dev/null ) -ne "200" ]; do
	FAIL=$((FAIL + 1))
	echo "Retrying $FAIL of $MAXFAIL"
	sleep 3
	if [ "$FAIL" -gt "$MAXFAIL" ]; then
		echo "ERROR: server seems not to be up, so I'm giving up"
		exit 1
	fi
done

pushd cfme-rhconsulting-scripts
make install
popd

pushd automate
miqimport domain CloudForms_Essentials `pwd`
popd

pushd service_dialogs
miqimport service_dialogs `pwd`
popd

pushd buttons
miqimport buttons `pwd`
popd

pushd reports
miqimport reports `pwd`
popd

pushd control
miqimport policies `pwd`
popd

#pushd alerts
#miqimport buttons `pwd`
#popd

pushd roles
miqimport roles `pwd`/roles.yml
popd

pushd service_catalogs
miqimport service_catalogs `pwd`
popd
