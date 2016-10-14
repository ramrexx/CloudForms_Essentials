#!/bin/sh

GIT_ROOT=https://github.com/jeffwarnica/CloudForms_Essentials
DID_REGISTER=no

cleanup() {
	if [ "yes" = $DID_REGISTER ] ; then
		subscription-manager unregister
	fi
}
trap cleanup 0

if !  subscription-manager status ; then
	DID_REGISTER=yes
	echo "You must subscribe to RHN to fetch some tools. This tool will unsubscribe	this appliance when it is finished."
	subscription-manager register
	subscription-manager attach
fi


yum install -y git nano

git clone $GIT_ROOT
cd CloudForms_Essentials

./install.sh
