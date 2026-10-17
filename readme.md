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
