**[Русский](#ru) | [English](#en)**

<a name="ru"></a>

# Windows 11 в QEMU/KVM на MX Linux

Схема та же, что у Debian-ВМ (`qemudebian`). Для Windows поменяются четыре вещи:

- **UEFI и TPM 2.0.** Без них Windows 11 не встанет. Нужны пакеты `ovmf` и `swtpm`.
- **Драйверы virtio.** У Windows их нет из коробки, поэтому при установке подключаем второй ISO `virtio-win.iso`.
- **Мышь.** Вместо `virtio-tablet` берём `usb-tablet`, он работает без драйвера.
- **Часы.** Добавляем `-rtc base=localtime`, иначе часы Windows будут сдвинуты.

## 1. Пакеты на MX Linux

```bash
sudo apt install qemu-system-x86 qemu-utils ovmf swtpm swtpm-tools \
     libvirt-daemon-system virt-viewer
egrep -c '(vmx|svm)' /proc/cpuinfo   # должно быть больше 0, иначе включите виртуализацию в BIOS
```

## 2. Мост virbr0, как на Debian

В MX по умолчанию sysvinit, поэтому `service`, а не `systemctl`:

```bash
sudo service libvirtd start
sudo virsh net-start default
sudo virsh net-autostart default
sudo mkdir -p /etc/qemu
echo "allow virbr0" | sudo tee /etc/qemu/bridge.conf
```

## 3. Диск, UEFI-переменные, TPM, ISO

```bash
cd /var/lib/libvirt/images
sudo qemu-img create -f qcow2 win11.qcow2 80G
sudo cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd win11_VARS.fd
sudo mkdir -p win11-tpm
sudo wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
# Win11.iso скачайте с microsoft.com/software-download и положите сюда же
```

## 4. Скрипт запуска

Скрипт лежит рядом: [`win11.sh`](win11.sh).

```bash
chmod +x win11.sh
./win11.sh
```

Подключение к экрану из другого терминала:

```bash
remote-viewer spice://localhost:5931
```

## 5. Установка Windows

1. Сразу после старта появится «Press any key to boot from CD». Успейте нажать любую клавишу в окне viewer'а.
2. Установщик не увидит диск. Нажмите «Загрузить драйвер» и выберите на CD с virtio `viostor\w11\amd64`, после этого диск появится.
3. Сети на этапе установки не будет. Чтобы создать локальную учётку без интернета, нажмите Shift+F10 и введите `start ms-cxh:localonly`. На старых сборках вместо этого работает `OOBE\BYPASSNRO`.
4. После установки откройте CD с virtio и запустите `virtio-win-guest-tools.exe`. Он поставит драйверы сети, QXL-видео, буфер обмена SPICE и остальное.
5. Потом строки с `Win11.iso` и `virtio-win.iso` из скрипта можно удалить.

## Проблемы при установке

### Установщик не видит диск

Это нормально. Диск подключён как virtio (`if=virtio`), а у установщика Windows нет драйвера virtio.

Маленький размер файла `win11.qcow2` (около 384 КБ) тоже нормальный. qcow2 растёт по мере записи. Проверка: `sudo qemu-img info /var/lib/libvirt/images/win11.qcow2` должна показать `virtual size: 80 GiB`.

Как подгрузить драйвер:

1. На экране выбора диска нажмите **«Загрузить драйвер»** (Load driver), затем **«Обзор»** (Browse).
2. Откройте CD с меткой **virtio-win** и папку `viostor\w11\amd64`. Нажмите OK.
3. Выберите **Red Hat VirtIO SCSI controller** и нажмите «Далее».
4. Появится «Незанятое пространство на диске 0, 80 ГБ». Выберите его и продолжайте установку.

Если драйвер не появляется в списке, снимите галочку «Скрыть драйверы, несовместимые с оборудованием» и проверьте, что выбрана `w11\amd64`, а не `w10` или `ARM64`.

Совет: там же можно сразу загрузить драйвер сети `NetKVM\w11\amd64`. Тогда сеть будет работать уже во время установки.

### Установка начата без драйвера сети NetKVM

Возвращаться и начинать заново не нужно. Драйвер сети ставится на любом этапе.

**Вариант 1: на экране «Подключитесь к сети» (OOBE).** Когда Windows не видит сетевую карту, на этом экране обычно есть кнопка **«Установить драйвер»** (Install driver). Нажмите её и укажите на CD virtio папку `NetKVM\w11\amd64`.

**Вариант 2: через командную строку (если кнопки нет).** На том же экране нажмите **Shift+F10**.

1. Найдите букву диска с virtio. Обычно это `D:` или `E:`:
   ```
   dir D:\
   dir E:\
   ```
   Нужен тот диск, где лежат папки `NetKVM`, `viostor` и другие.
2. Поставьте драйвер (здесь `E:` для примера, подставьте свою букву):
   ```
   pnputil /add-driver E:\NetKVM\w11\amd64\*.inf /install
   ```
3. Закройте окно. Сеть должна появиться через несколько секунд. Если не появилась, нажмите «Назад» или «Повторить» на экране сети.

**Вариант 3: отложить на потом.** Нажмите Shift+F10 и введите `start ms-cxh:localonly`. Так создаётся локальная учётка без сети. Уже в Windows запустите с CD virtio `virtio-win-guest-tools.exe`. Он поставит сеть и остальные драйверы разом.

## Примечания

- Скрипт не проверялся запуском. Расчёт на то, что MX Linux на базе Debian 12 и пути OVMF такие же, как в Debian. Если файлов `OVMF_CODE_4M.secboot.fd` и `OVMF_VARS_4M.ms.fd` нет, проверьте реальные имена командой `ls /usr/share/OVMF/`.
- MAC-адрес изменён на `...:57`, а порт SPICE на 5931, чтобы не было конфликта, если обе ВМ окажутся в одной сети.
- Если нужна Windows 10, TPM и Secure Boot можно убрать. Тогда без строк `swtpm`, `-chardev`, `-tpmdev`, `-device tpm-tis` и `-global ...secure...`, а `smm=on` и файлы `.secboot`/`.ms` тоже не обязательны.

---

<a name="en"></a>

# Windows 11 on QEMU/KVM on MX Linux

Same setup as the Debian VM (`qemudebian` alias). Four things change for Windows:

- **UEFI and TPM 2.0.** Windows 11 won't install without them. You need the `ovmf` and `swtpm` packages.
- **virtio drivers.** Windows doesn't ship them, so a second ISO, `virtio-win.iso`, is attached during installation.
- **Mouse.** `usb-tablet` instead of `virtio-tablet`, because it works without a driver.
- **Clock.** `-rtc base=localtime` is added, otherwise the Windows clock will be off.

## 1. Packages on MX Linux

```bash
sudo apt install qemu-system-x86 qemu-utils ovmf swtpm swtpm-tools \
     libvirt-daemon-system virt-viewer
egrep -c '(vmx|svm)' /proc/cpuinfo   # must be greater than 0, otherwise enable virtualization in BIOS
```

## 2. virbr0 bridge, same as on Debian

MX uses sysvinit by default, so it's `service`, not `systemctl`:

```bash
sudo service libvirtd start
sudo virsh net-start default
sudo virsh net-autostart default
sudo mkdir -p /etc/qemu
echo "allow virbr0" | sudo tee /etc/qemu/bridge.conf
```

## 3. Disk, UEFI variables, TPM, ISOs

```bash
cd /var/lib/libvirt/images
sudo qemu-img create -f qcow2 win11.qcow2 80G
sudo cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd win11_VARS.fd
sudo mkdir -p win11-tpm
sudo wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
# Download Win11.iso from microsoft.com/software-download and put it here too
```

## 4. Launch script

The script is in this repo: [`win11.sh`](win11.sh).

```bash
chmod +x win11.sh
./win11.sh
```

Connect to the display from another terminal:

```bash
remote-viewer spice://localhost:5931
```

## 5. Installing Windows

1. Right after start you'll see "Press any key to boot from CD". Press any key in the viewer window in time.
2. The installer won't see the disk. Click "Load driver" and pick `viostor\w11\amd64` on the virtio CD; the disk will then appear.
3. There's no network during installation. To create a local account without internet, press Shift+F10 and run `start ms-cxh:localonly`. On older builds, `OOBE\BYPASSNRO` works instead.
4. After installation, open the virtio CD and run `virtio-win-guest-tools.exe`. It installs the network, QXL video, SPICE clipboard and other drivers.
5. After that, the `Win11.iso` and `virtio-win.iso` lines can be removed from the script.

## Installation problems

### The installer doesn't see the disk

This is expected. The disk is attached as virtio (`if=virtio`), and the Windows installer has no virtio driver.

The small size of `win11.qcow2` (about 384 KB) is also fine. qcow2 grows as data is written. Check: `sudo qemu-img info /var/lib/libvirt/images/win11.qcow2` should show `virtual size: 80 GiB`.

How to load the driver:

1. On the disk selection screen, click **Load driver**, then **Browse**.
2. Open the CD labeled **virtio-win** and the folder `viostor\w11\amd64`. Click OK.
3. Select **Red Hat VirtIO SCSI controller** and click Next.
4. "Drive 0 Unallocated Space, 80 GB" appears. Select it and continue.

If the driver doesn't show up in the list, uncheck "Hide drivers that aren't compatible with this computer's hardware" and make sure you picked `w11\amd64`, not `w10` or `ARM64`.

Tip: on the same screen you can also load the network driver `NetKVM\w11\amd64`. Then the network works during installation.

### Installation started without the NetKVM network driver

No need to go back or start over. The network driver can be installed at any stage.

**Option 1: on the "Let's connect you to a network" screen (OOBE).** When Windows sees no network adapter, this screen usually has an **Install driver** button. Click it and point it to `NetKVM\w11\amd64` on the virtio CD.

**Option 2: from the command line (if there's no button).** On the same screen press **Shift+F10**.

1. Find the drive letter of the virtio CD. Usually it's `D:` or `E:`:
   ```
   dir D:\
   dir E:\
   ```
   You need the drive with the `NetKVM`, `viostor` and other folders.
2. Install the driver (`E:` is an example, use your letter):
   ```
   pnputil /add-driver E:\NetKVM\w11\amd64\*.inf /install
   ```
3. Close the window. The network should appear within a few seconds. If it doesn't, click Back or Retry on the network screen.

**Option 3: do it later.** Press Shift+F10 and run `start ms-cxh:localonly`. This creates a local account without network. Once in Windows, run `virtio-win-guest-tools.exe` from the virtio CD. It installs the network and all other drivers at once.

## Notes

- The script assumes MX Linux is based on Debian 12 and the OVMF paths match Debian's. If `OVMF_CODE_4M.secboot.fd` and `OVMF_VARS_4M.ms.fd` don't exist, check the actual names with `ls /usr/share/OVMF/`.
- The MAC address is `...:57` and the SPICE port is 5931, so they don't clash with the Debian VM if both run on the same network.
- For Windows 10 you can drop TPM and Secure Boot: remove the `swtpm`, `-chardev`, `-tpmdev`, `-device tpm-tis` and `-global ...secure...` lines; `smm=on` and the `.secboot`/`.ms` files are then optional too.
