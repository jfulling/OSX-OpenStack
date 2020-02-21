# OSX-OpenStack
Sample research demonstrating how to apply specialized KVM virtualization to an OpenStack instance.

## Disclaimer
All testing was performed on genuine Apple hardware. I do not claim responsibility for how this research is used. If you decide to emulate OSX, ensure that any attempts are in compliance with the legal terms in the EULA.


## Description

This is a repository inspired largely from the [OSX-KVM repo from user *kholia*](https://github.com/kholia/OSX-KVM). I wanted to learn how to fit an OpenStack instance with the necessary settings to virtualize an OSX instance in OpenStack, focusing specifically on High Sierra. Based on the repo linked above, there are a number of challenges that need to be addressed:

---

## Challenges
1. UEFI Booting
2. Attaching the AppleSMC device with the proper key
3. Ensuring the proper QEMU version is used
4. Ensuring the right machine type is used (`pc-q35-2.9`)
5. Attaching a USB keyboard and mouse
6. Consolidation into a single HDD
7. CPU - SSE4.1 feature
8. Using the Penryn CPU model for virtualization
9. Attaching an Apple MAC address to the network adapter


---

## UEFI Booting

At least in the *Pike* release, OpenStack supports the ability to boot instances with UEFI. However, the OpenStack operator needs to add OVMF support to all applicable *Nova* (Compute) hosts. In Ubuntu 18.04, this can be done simply via the following command:

```
sudo apt-get update -y && sudo apt-get install ovmf -y
```

Since *kholia*'s repo contains a patched OVMF file, OpenStack will need to serve up the patched OVMF file to our VM. In order to accomplish this, the patched OVMF files need to be replaced with the patched versions:

```
cp OSX-KVM/OVMF_CODE.fd /usr/share/OVMF/OVMF_Code.fd
cp OSX-KVM/OVMF_VARS-1024x768.fd /usr/share/OVMF/OVMF_VARS.fd
```

Once these are in place, OpenStack will attempt to use these files when UEFI booting. It is worth noting that OpenStack will by default create a copy of /usr/share/OVMF/OVMF_VARS.fd and move it into /var/lib/libvirt/qemu/nvram/instance-XXXXXXXX_VARS.fd and use it as the instance's NVRAM.

When using this feature in OpenStack, simply add the `hw_firmware_type` property to the image and set the value to `uefi`.

---

## Attaching the AppleSMC Device with the Proper Key

#### How are Instances Created?

This was by far the most difficult thing to accomplish in this research. QEMU lists the isa-applesmc device as a miscellaneous device, and from what I saw, the only way to add this device to an instance is to modify the instance generation `config.py` and `driver.py` files in `nova/virt/libvirt/`. Since I have no experience developing in the Nova project, I defaulted to a more ephemeral solution.

When OpenStack creates an instance in libvirt, an operator can use the virsh tool to see all the instances running on the host. The ``virsh list`` command will list the instances, their virsh IDs, and their names. OpenStack instances are named with instance-XXXXXXXX format, where each new instance is an incremented value from the last.
Example: instance-00000001, instance-00000002 etc.

When OpenStack creates instances, it generates .xml files containing the configuration and writes them to the disk. In regards to instance configuration, These files are read-only, and any modifications made to them are quickly destroyed. However, since OpenStack is just taking advantage of the libvirt APIs, we can manually make libvirt calls to define the instance ourselves.

#### How Can the AppleSMC Device be Added?

In order to add the AppleSMC device with the secret key, we can modify the libvirt XML file for the instance to add the device directly via the <qemu:commandline> tag, or attempt to add the ISA device in the XML manually. Since it's easiest to just update the XML with the <qemu:commandline> tag, I decided to go with the following modifications to the instance XML file.

Enabling usage of the <qemu:commandline> parameter:

Replace

```<domain type='kvm'>```

With

```<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>```
 
Then, add the AppleSMC device before the closing </domain> tag
```
<qemu:commandline>
  <qemu:arg value='-device'/>
  <qemu:arg value='isa-applesmc,osk=SMC-Secret-Key'/>
</qemu:commandline>
```

#### How do These Changes Remain Persistent?

The XML file now configures the instance to add the AppleSMC device. We could modify this file manually or use ``virsh edit`` but any changes to the instance this way will be immediately destroyed by OpenStack. To get around this, I found that it's possible to manually destroy and redefine the instance in libvirt while still keeping the instance available in OpenStack. So in order to maintain some level of persistence, I found the following process could be used:
```
#!/bin/bash

#Create a local backup copy of the instance
cp /etc/libvirt/qemu/instance-XXXXXXXX.xml .

#Add the configuration to the instance
sed -i (Add the xmlns to the top and add the qemu command line)

#Destroy the current instance
virsh destroy instance-XXXXXXXX

#Copy over the new XML
cp instance-XXXXXXXX.xml /etc/libvirt/qemu/

#Create and start the instance
virsh create /etc/libvirt/qemu/instance-XXXXXXXX.xml
virsh start instance-XXXXXXXX
```

The instance will now continue running with the modifications until it is assigned a hard reboot from OpenStack. I've noticed that if the VM is destroyed long enough for OpenStack to register that the VM is powered off, the VM itself will keep powering off frequently until OpenStack has the instance registered as running.

I found that scripting these changes prevents OpenStack from noticing the instance is down, and allows the end user to connect to the console directly with the changes added to the VM.

---

## Ensuring the Proper QEMU Version is Used

Unfortunately, simply updating QEMU and libvirt via a package manager doesn't always work. It's possible to build QEMU and replace the binaries called by OpenStack, or you can use an OS listed [in this article](https://wiki.openstack.org/wiki/LibvirtDistroSupportMatrix) that contains QEMU 2.9 or greater by default. 

I chose to deploy Ubuntu 18 which quickly solved this issue.

---

## Ensuring the Right Machine Type is Used (`pc-q35-2.9`)

OpenStack allows a user to change the instance machine type during the image importing stage. This can be done simply in the image metadata upon import.

---

## Attaching a USB Keyboard and Mouse

In order to enable mouse and keyboard support via USB emulation (to match *kholia*'s project), I noticed that the `-device usb-kbd` and `-device usb-tablet` keywords don't appear to work with some instances.

Instead, I've had more success with the `--usbdevice tablet` and `--usbdevice keyboard` command line parameters, which I believe [have been deprecated](https://lists.gnu.org/archive/html/qemu-devel/2017-05/msg04503.html).

---

## Consolidation into a Single HDD

Following the instructions in *kholia*'s repo, it is possible to create a single bootable OSX HDD. Since that is not a focus of this repo (as it does not explore how OpenStack instance configuration works), I will not be covering the steps here.

---

## SSE4.1 Feature

At least for High Sierra, it is critical that the *Nova* compute host has several CPU features, one of them being SSE4.1.

This information can be found with the below command:

```
cat /proc/cpuinfo
```

*kholia*'s OSX-KVM repo has a more comprehensive list of CPU requirements for each OSX version.

---

## Using the Penryn CPU model for Virtualization

At the time of this research, I was not able to find a non-ephemeral way of emulating the proper CPU type. Instead, the approach I took was to [simply change the *Nova* `libvirt` settings](https://docs.openstack.org/mitaka/config-reference/compute/hypervisor-kvm.html):

In `/etc/nova/nova.conf` on the target compute host:

```
[libvirt]
cpu_mode = custom
cpu_mode = Penryn
```

---

## Attaching a Custom MAC Address to the Network Adapter

In OpenStack, an appropriate MAC address can be added by simply creating a network port with a manually defined MAC, and attaching it to the instance as the only active port.

---

## Putting it All Together

The `patch-openstack-full.sh` script in this repo contains an automated way to update instances running on the target compute host. The script will source an `openrc` file to gather credentials for the OpenStack deployment, and query all instances running on the *Nova* compute host. It will grep out metadata for an `os=OSX` metadata tag, and then update the XML in the method described above.

To run the script effectively, the following steps must be performed:

1. Ensure the CPU requirements exist for all relevant *Nova* compute hosts
2. Ensure the CPU model is set properly on all relevant *Nova* compute hosts
3. Upload the target image, with the proper metadata tags
4. Create a network port for the instance with a custom MAC address
5. Create a flavor with the proper CPU and RAM specs (e.g. 2 cores, 3GB)
6. Begin deploying the instance, adding a custom `os` metadata tag with the value of `OSX`, assigning the instance the proper network port and flavor
7. Once the instance is deployed, run the script (ideally on a `cron` schedule -- the script has checks in place to make sure images aren't needlessly destroyed).

Read the XML, and all the setting should be in place, showing that the script ran successfully!
