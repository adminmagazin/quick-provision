#!/bin/bash
#
# Get Ubuntu 14.04 cloud image, create qemu image and user data image, create VM

IMGDIR=/var/lib/libvirt/images
CLOUDIMG=trusty-server-cloudimg-amd64-disk1.img
VMIMG=trusty-cloudimg-amd64.img
USERIMG=trusty-userdata.img
VMNAME=trusty1
RAM=524288 # memory in Kbytes

echo "please enter password for VM"
read -s password1
echo "please re-enter password for verification"
read -s password2
if [[ "$password1" != "$password2" ]]; then
   echo "passwords do not match, please start over." 1>&2
   exit 1
fi

# check for root permissions
if [[ $EUID -ne 0 ]]; then
   echo "this script must be run as root." 1>&2
   exit 1
fi

which cloud-localds > /dev/null
if [ $? -ne 0 ]; then
  echo "cloud-localds not found. Please install cloud-image-tools."
  exit
fi

if [ ! -d "$IMGDIR" ]; then
   echo "$IMGDIR does not exist."
   exit
fi

cd "$IMGDIR"

if [ -e "$VMIMG" ]; then
   echo "$IMGDIR/$VMIMG exists, exiting."
   exit
fi

if [ -e "$CLOUDIMG" ]; then
   echo "$CLOUDIMG exists, skipping download"
else 
   wget https://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img
fi

echo "converting and resizing image..."
qemu-img convert -O qcow2 "$CLOUDIMG" "$VMIMG"
qemu-img resize "$VMIMG" +3G

USERDATA=$( cat<<EOF
#cloud-config
password: $password1
chpasswd: { expire: False }
ssh_pwauth: True
EOF
)

XML=$( cat <<EOF
<domain type='kvm'>
    <name>$VMNAME</name>
    <memory unit='KiB'>$RAM</memory>
    <os>
        <type>hvm</type>
        <boot dev="hd" />
    </os>
    <features>
        <acpi/>
    </features>
    <vcpu>1</vcpu>
    <devices>
       <emulator>/usr/bin/kvm-spice</emulator>
        <disk type='file' device='disk'>
            <driver type='qcow2' cache='none'/>
            <source file='/var/lib/libvirt/images/$VMIMG'/>
            <target dev='vda' bus='virtio'/>
        </disk>
        <disk type='file' device='disk'>
            <source file='/var/lib/libvirt/images/$USERIMG'/>
            <target dev='vdb' bus='virtio'/>
        </disk>
        <interface type='network'>
            <source network='default'/>
                <model type='virtio'/>
        </interface>
	    <graphics type='spice' port='5930' autoport='no'/>
	    <video>
	      <model type='qxl' vram='65536' heads='1'/>
	      <alias name='video0'/>
	      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
	    </video>
    </devices>
</domain>
EOF
)

echo "creating userdata image..."
cloud-localds "$USERIMG" <(echo "$USERDATA")

echo "creating vm..."
virsh define <(echo "$XML") 

echo "starting vm..."
virsh start "$VMNAME"

echo "done."
echo "you can now log into your VM with the username 'ubuntu' and the password you entered."
cd -
