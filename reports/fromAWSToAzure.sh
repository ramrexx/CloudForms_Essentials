#!/bin/bash
echo "IMPORTANT: execute me in the same folder as the Amazon reports, I'll generate the Azure equivalents"
for r in *Amazon*;
do
	#prepend a number 9 on the index
	newname=9${r/Amazon/Azure}
	cp $r $newname
	sed 's/Amazon/Azure/g' $newname -i
	sed 's/amazon/azure/g' $newname -i
	echo $newname
done
