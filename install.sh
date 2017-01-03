#!/bin/sh
set -x 

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

pushd cfme-rhconsulting-scripts
make install
popd

pushd automate
miqimport domain CloudForms_Essentials `pwd`
popd

#pushd dialogs
#miqimport provision_dialogs `pwd`
#miqimport service_dialogs `pwd`
#popd

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
