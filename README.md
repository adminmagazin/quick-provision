#Ubuntu Quick Provisioning

This script downloads an Ubuntu 14.04 cloud image, resizes the image, writes another image with user data, then creates a KVM virtual machine and boots it.

##Features
* customize Ubuntu cloud image and provision it as a KVM virtual machine
* uses SPICE for VM display
* just basic functionality, if you want more, go ahead, fork and send pull request

##Requires
* Linux KVM, virsh (libvirt-bin), cloud-localds (cloud-image-utils), wget
    
##Usage

Just run the script as root or with sudo.   

##Todo
* more options for VM creation, such as disk size, RAM, ...
* support other Linux distributions

##License 

This script is licensed under the BSD License

