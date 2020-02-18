#!/bin/bash

#Source the openrc file
source openrc

#Grab a list of instances with the os=OSX property
for uuid in $(openstack server list --long | grep --ignore-case "\os='\?OSX'\?" | cut -d '|' -f2 | tr -d ' '); do

	echo -e "\033[1;33m[+] Found UUID:\t\033[1;32m$uuid\033[0m"
	#Find the instance ID
	instance=$(grep -r "<uuid>$uuid</uuid>" /etc/libvirt/qemu | grep -v NOSTATE | egrep -o instance-[a-f0-9]*)
	echo -e "\033[1;33m[+] Found matching instance ID:\t\033[1;36m$instance\033[0m"
	#Check to see if it's already been patched to avoid unnecessary reboot
	if grep -q "APPLE_SMC_SECRET_KEY_HERE" "/etc/libvirt/qemu/$instance.xml"; then
		echo -e "\033[1;31m[!] Patch detected! Skipping $instance...\033[0m"
		continue;
	fi

	#Make a backup of the config
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Preparing a backup\033[0m"
	mkdir -p /tmp/xmlbackups/original /tmp/xmlbackups/modified
	cp "/etc/libvirt/qemu/$instance.xml" /tmp/xmlbackups/original
	cp "/etc/libvirt/qemu/$instance.xml" /tmp/xmlbackups/modified

	#Modify the new XML copy
	#Start with allowing extended QEMU XML attributes
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Extending XML schema\033[0m"
	sed "s/<domain type='kvm'>/<domain type='kvm' xmlns:qemu='http:\/\/libvirt.org\/schemas\/domain\/qemu\/1.0'>/" -i "/tmp/xmlbackups/modified/$instance.xml"

	#Modify the new XML copy
	#Start with allowing extended QEMU XML attributes
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Extending XML schema\033[0m"
	sed "s/<domain type='qemu'>/<domain type='qemu' xmlns:qemu='http:\/\/libvirt.org\/schemas\/domain\/qemu\/1.0'>/" -i "/tmp/xmlbackups/modified/$instance.xml"

	#Delete the closing domain tag to append our qemu:commandline args
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Moving final domain tag\033[0m"
	sed "s/<\/domain>//" -i "/tmp/xmlbackups/modified/$instance.xml"

	#Add the qemu:commandline tags
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Adding <qemu:commandline>...\033[0m"
	echo "  <qemu:commandline>" >> "/tmp/xmlbackups/modified/$instance.xml"

	#Add the AppleSMC device with its OSK
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Adding AppleSMC Device with Key\033[0m"
	echo "    <qemu:arg value='-device'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
	echo "    <qemu:arg value='isa-applesmc,osk=APPLE_SMC_SECRET_KEY_HERE'/>" >> "/tmp/xmlbackups/modified/$instance.xml"

	#Add the USB Keyboard/Tablet Feature
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Adding USBTablet Features\033[0m"
#	echo "    <qemu:arg value='-device'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
#	echo "    <qemu:arg value='usb-kbd'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
#	echo "    <qemu:arg value='-device'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
#	echo "    <qemu:arg value='usb-tablet'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
	echo "    <qemu:arg value='--usbdevice'/>" >>"/tmp/xmlbackups/modified/$instance.xml"
	echo "    <qemu:arg value='tablet'/>" >> "/tmp/xmlbackups/modified/$instance.xml"
	echo "    <qemu:arg value='--usbdevice'/>" >>"/tmp/xmlbackups/modified/$instance.xml"
	echo "    <qemu:arg value='keyboard'/>" >> "/tmp/xmlbackups/modified/$instance.xml"

	#Add the closing qemu:commandline tags
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Close qemu:commandline parameter\033[0m"
	echo "  </qemu:commandline>" >> "/tmp/xmlbackups/modified/$instance.xml"

	#Add the closing domain tag
	echo -e "\033[1;33m[+] \033[1;36m$instance:\033[1;33m Add closing Domain tag\033[0m"
	echo "</domain>" >> "/tmp/xmlbackups/modified/$instance.xml"

	#Destroy the instance
	echo -e "\033[1;33m[!] \033[1;36m$instance:\033[1;33m Destroying instance...\033[0m"
	virsh destroy "$instance"

	#Move in the xml for the new instance
	echo -e "\033[1;33m[!] \033[1;36m$instance:\033[1;33m Modifying Instance...\033[0m"
	cp "/tmp/xmlbackups/modified/$instance.xml" /etc/libvirt/qemu

	#Re-create the new instance
	echo -e "\033[1;33m[!] \033[1;36m$instance:\033[1;33m Creating instance...\033[0m"
	virsh create "/etc/libvirt/qemu/$instance.xml"
done
