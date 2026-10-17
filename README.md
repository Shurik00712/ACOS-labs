# Лабораторная работа №1

## Запуск скрипта

**Linux:**
```bash
./clear_logs.sh <LOG_DIR> <THRESHOLD> <BACKUP_DIR>
LAB1_MAX_COMPRESSION=1 ./clear_logs.sh <LOG_DIR> <THRESHOLD> <BACKUP_DIR>
```

**Windows:**
```
clear_logs.bat <LOG_DIR> <THRESHOLD> <BACKUP_DIR>
set LAB1_MAX_COMPRESSION=1 && clear_logs.bat <LOG_DIR> <THRESHOLD> <BACKUP_DIR>
```

Параметры по умолчанию: `/log`, `70`, `/backup`.

## Запуск тестов

**Linux:** `./test_clear_logs.sh [LOG_DIR] [BACKUP_DIR] [SCRIPT]` - аргументы опциональны, по умолчанию `$HOME/lab1/log`, `$HOME/lab1/backup`, `./clear_logs.sh`.

**Windows:** `test_clear_logs.bat [LOG_DIR] [BACKUP_DIR] [SCRIPT]` - аргументы опциональны, по умолчанию `L:\log`, `C:\lab1\backup`, `clear_logs.ps1` рядом с батником. Можно задать значения и через переменные окружения `LOG_DIR`, `BACKUP_DIR`, `SCRIPT`.

## Как смонтировать диск для проверки

### Linux - образ диска через `losetup` (нужны права администратора)

```bash
dd if=/dev/zero of=test.img bs=1M count=1024
sudo losetup -f test.img
sudo mkfs.ext4 /dev/loop0
sudo mkdir /mnt/testlog
sudo mount /dev/loop0 /mnt/testlog
```

Отключить после проверки:

```bash
sudo umount /mnt/testlog
sudo losetup -d /dev/loop0
```

### Windows - виртуальный диск VHD/VHDX

Через «Управление дисками»:

1. Win + X - Управление дисками.
2. Действие - Создать виртуальный жёсткий диск.
3. Указать путь, размер, формат (VHD/VHDX), нажать ОК.
4. Инициализировать диск, создать том, назначить букву.

Через PowerShell (нужны права администратора):

```powershell
New-VHD -Path "C:\drive\test.vhdx" -SizeBytes 1GB -Dynamic
Mount-DiskImage -ImagePath "C:\drive\test.vhdx"
```

Отключить после проверки:

```powershell
Dismount-DiskImage -ImagePath "C:\drive\test.vhdx"
```
