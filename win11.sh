#!/bin/bash
IMG=/var/lib/libvirt/images

# TPM-эмулятор: запускается перед каждым стартом ВМ
sudo swtpm socket --tpm2 --daemon \
  --tpmstate dir=$IMG/win11-tpm \
  --ctrl type=unixio,path=$IMG/win11-tpm/sock

sudo qemu-system-x86_64 \
  -enable-kvm -m 8192 -smp 4 \
  -machine q35,smm=on \
  -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
  -drive if=pflash,format=raw,file=$IMG/win11_VARS.fd \
  -chardev socket,id=chrtpm,path=$IMG/win11-tpm/sock \
  -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
  -drive file=$IMG/win11.qcow2,if=virtio,format=qcow2 \
  -drive file=$IMG/Win11.iso,media=cdrom \
  -drive file=$IMG/virtio-win.iso,media=cdrom \
  -boot menu=on \
  -rtc base=localtime \
  -netdev bridge,br=virbr0,id=net0 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:57 \
  -vga qxl \
  -device qemu-xhci -device usb-tablet \
  -spice port=5931,disable-ticketing=on \
  -device intel-hda -device hda-duplex \
  -monitor stdio
