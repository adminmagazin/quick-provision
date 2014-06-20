#!/bin/bash
#
# Get Ubuntu 14.04 cloud image, create qemu image and user data image, create VM

IMGDIR=/var/lib/libvirt/images
RAM=524288 # memory in Kbytes

setup_images() {
   VMIMG=$1-cloudimg.img
   USERIMG=$1-userdata.img
}

setup_distro() {
   if [[ "$1" == "F" ]]; then
      CLOUDIMG=Fedora-x86_64-20-20140407-sda.qcow2
      IMGURL=http://download.fedoraproject.org/pub/fedora/linux/updates/20/Images/x86_64/$CLOUDIMG
      USERNAME=fedora
   elif [[ "$1" == "U" ]]; then
      CLOUDIMG=trusty-server-cloudimg-amd64-disk1.img
      IMGURL=https://cloud-images.ubuntu.com/trusty/current/$CLOUDIMG
      USERNAME=ubuntu
   else
      echo "no valid distro data found" 2>&1
      exit 1
   fi
}

cleanup() {
   cd $OLDPWD
   reset
   exit 1
}

trap 'cleanup' 2

# check for root permissions
if [[ $EUID -ne 0 ]]; then
   echo "this script must be run as root." 1>&2
   exit 1
fi

if [ ! -d "$IMGDIR" ]; then
   echo "$IMGDIR does not exist."
   exit 1
fi
cd "$IMGDIR"

DISTRO=""
while [ "$DISTRO" == "" ]; do
   read -p "which distro do you want do use (f)edora/(u)buntu?" reply
   reply=$(echo $reply | tr 'a-z' 'A-Z')
   if [[ "$reply" != "F" && "$reply" != "U" ]]; then
      continue
   else
      DISTRO=$reply
   fi
done

setup_distro $DISTRO

read -p "please enter name for vm:" VMNAME 

setup_images $VMNAME

# check for existing VM
virsh list --all | grep -q "$VMNAME"
if [ $? -eq 0 ]; then
   read -p "VM $VMNAME exists. delete? (y/n)" confirm
   confirm=$(echo $confirm | tr 'a-z' 'A-Z')
   if [[ "$confirm" != "Y" ]]; then
       echo "exiting" 1>&2
       exit 1
   else
      virsh destroy "$VMNAME" 
      virsh undefine "$VMNAME" 
      rm "$VMIMG"
   fi
fi

# check for existing VM image separately
if [ -e "$VMIMG" ]; then
   read -p "$IMGDIR/$VMNAME exists. delete? (y/n)" confirm
   confirm=$(echo $confirm | tr 'a-z' 'A-Z')
   if [[ "$confirm" != "Y" ]]; then
       echo "exiting" 1>&2
       exit 1
   else
      rm "$VMIMG"
   fi
fi

# check for cloud-localds tool
which cloud-localds > /dev/null
if [ $? -ne 0 ]; then
  echo "cloud-localds not found. Please install cloud-image-tools."
  exit 1
fi

# check for cloud image tool
if [ -e "$CLOUDIMG" ]; then
   echo "$CLOUDIMG exists, skipping download"
else 
   wget $IMGURL
fi

# password for "ubuntu" user in VM
read -sp "please enter password for VM:" password1 ; echo
read -sp "please re-enter password for verification:" password2 ; echo
if [[ "$password1" != "$password2" ]]; then
   echo "passwords do not match, please start over." 1>&2
   exit 1
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
echo "you can now log into your VM with the username '$USERNAME' and the password you entered."
cd $OLDPWD
