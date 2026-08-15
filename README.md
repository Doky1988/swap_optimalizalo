<h1 align="center">💾 Swap & Memória Optimalizáló</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Debian-✓-red?style=for-the-badge&logo=debian" />
  <img src="https://img.shields.io/badge/Ubuntu-✓-orange?style=for-the-badge&logo=ubuntu" />
  <img src="https://img.shields.io/badge/Bash-Script-black?style=for-the-badge&logo=gnubash" />
  <img src="https://img.shields.io/badge/Author-Doky-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Licenc-MIT-yellow?style=for-the-badge" />
</p>

<p align="center"><strong>Interaktív bash szkript Debian/Ubuntu VPS-ek swap fájl létrehozásához és mérsékelt memóriaoptimalizáláshoz.</strong></p>

<p align="center">VPS-barát swap méretezés, konzisztens meglévő-fájl kezelés, biztos sysctl perzisztencia — biztonsági mentésekkel, dry-run móddal és visszaállítási lehetőséggel.</p>

---

## 📌 Funkciók

- **Root ellenőrzés** — csak root jogosultsággal futtatható
- **VPS-barát swap méretezés** — RAM méret alapján rögzített, kiszámítható swap méret (≤4 GB RAM → 2 GB, <64 GB → 4 GB, ≥64 GB → 8 GB)
- **Egységes meglévő-fájl kezelés** — ha a `/swapfile` már megfelelő méretű, nem cseréli feleslegesen; csak méreteltérésnél kérdez
- **Meglévő swap biztonsága** — ha nemet mondasz a cserére, a meglévő swap **aktív marad**, nem lesz véletlenül lekapcsolva
- **Több swap felismerése** — ha a rendszeren más swap is aktív, a script jelzi, és **nem nyúl hozzá**
- **Swap fájl létrehozása és aktiválása** — `fallocate` vagy `dd` módszerrel, `/etc/fstab` bejegyzéssel, `chmod 600` jogosultsággal
- **Memória fókuszú sysctl finomhangolás** — kizárólag `vm.swappiness`, `vm.vfs_cache_pressure`, `vm.dirty_ratio`, `vm.dirty_background_ratio` (hálózati tuning nélkül)
- **Garantált perzisztencia** — a kívánt sysctl értékek mindig bekerülnek az `/etc/sysctl.conf`-ba, így reboot után is érvényben maradnak
- **Dry-run mód** — `--dry-run` kapcsolóval minden művelet szimulálható, tényleges módosítás nélkül
- **Visszaállítás** — `--rollback` kapcsolóval az eredeti sysctl értékek visszaállíthatók (csak a script által kezelt kulcsok)
- **Interaktív és automatikus mód** — alapértelmezetten minden lépésnél megerősítést kér, `--force` / `-y` flaggel teljesen automatikus
- **Biztonsági mentések** — minden módosítás előtt időbélyegzős mentés készül az eredeti sysctl értékekről és konfigurációs fájlokról
- **Részletes naplózás** — minden művelet naplózva a `/var/log/swap_optimalizalo.log` fájlba
- **Dinamikus terminál igazítás** — a fejléc automatikusan középre igazodik a terminál szélességéhez

---

## 📦 Rendszerkövetelmények

- Debian 12/13 vagy Ubuntu 22.04/24.04
- Root jogosultság (`sudo`)

---

## 📥 Használat

### Letöltés és futtatás

```bash
wget https://raw.githubusercontent.com/Doky1988/swap_optimalizalo/main/swap_optimalizalo.sh
chmod +x swap_optimalizalo.sh
sudo ./swap_optimalizalo.sh
```

### Egy paranccsal

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Doky1988/swap_optimalizalo/main/swap_optimalizalo.sh)
```

### Dry-run (ajánlott első futtatáskor)

```bash
sudo ./swap_optimalizalo.sh --dry-run
```

---

## ⚙️ Kapcsolók

| Kapcsoló | Leírás |
|----------|--------|
| `--dry-run` | Csak szimuláció — mindent megjelenít, de nem módosít semmit |
| `--rollback` | Eredeti sysctl beállítások visszaállítása a biztonsági mentésből |
| `--swap-size <MB>` | Swap fájl méretének kézi megadása MB-ban (min. 512, felülbírálja az automatikus kalkulációt) |
| `--swap-file <PATH>` | Swap fájl elérési útja (alapértelmezett: `/swapfile`) |
| `--no-tune` | Csak swap fájl létrehozása — sysctl finomhangolás nélkül |
| `--remove-swap` | Swap fájl + `/etc/fstab` bejegyzés eltávolítása |
| `--force`, `-y` | Interaktív megerősítések átugrása — teljesen automatikus futtatás |
| `--help` | Súgó megjelenítése |

---

## 📊 Swap méretezési logika

| RAM méret | Swap méret | Példa |
|-----------|------------|-------|
| ≤ 4 GB | 2 GB | 2 GB RAM → **2 GB** swap |
| 5–63 GB | 4 GB | 16 GB RAM → **4 GB** swap |
| ≥ 64 GB | 8 GB | 128 GB RAM → **8 GB** swap |

Kézi méret megadása a `--swap-size` kapcsolóval lehetséges (minimum 512 MB).

---

## 🔧 Sysctl optimalizációk

A script **kizárólag memória fókuszú** — hálózati tuningot és `vm.min_free_kbytes` módosítást nem végez.

| Paraméter | Alapértelmezett | Optimalizált | Hatás |
|-----------|-----------------|-------------|-------|
| `vm.swappiness` | 60 | 10 | Ritkább swap használat |
| `vm.vfs_cache_pressure` | 100 | 50 | Inode/dentry cache agresszívabb megtartása |
| `vm.dirty_ratio` | 20 | 10 | Kevesebb dirty adat lehet a RAM-ban |
| `vm.dirty_background_ratio` | 10 | 5 | A kernel korábban elkezdi kiírni a dirty adatokat |

> **Perzisztencia garancia:** ha a tuning engedélyezve van, a kívánt értékek **minden esetben** bekerülnek az `/etc/sysctl.conf`-ba — akkor is, ha a futás pillanatában már megfelelőek. Így nem fordulhat elő, hogy a script futása után minden jó, de reboot után visszaáll az alapértelmezett érték.

> **Irányfüggő alkalmazás:** futásidőben a script csak akkor módosítja az értéket, ha az javítást jelent — a már megfelelő értékhez nem nyúl.

---

## 🖥️ Példa kimenet

```
╔══════════════════════════════════════════════════╗
║           Swap & Memória Optimalizáló            ║
╚══════════════════════════════════════════════════╝

  Rendszerinformációk:
  ─────────────────────────────────────────────
  Kernel:        6.12.86+deb13-amd64
  Disztribúció:  Debian GNU/Linux 13 (trixie)
  RAM:           3.7 GB
  Jelenlegi swap:0 MB
  Lemez szabad:  37G


Műveletek megerősítése

  A következő műveletek kerülnek végrehajtásra:
    - Swap fájl létrehozása: /swapfile (2.0 GB)
    - Rendszerparaméterek (sysctl) finomhangolása

[?] Folytatjuk a műveleteket? [y/N]: y

1/2 Swap fájl létrehozása

[INFO] Swap fájl létrehozása: /swapfile (2.0 GB)...
Setting up swapspace version 1, size = 2 GiB (2147479552 bytes)
no label, UUID=ad88f124-5c49-4dee-ae1e-6749fff2d7ec
[OK]   Swap fájl létrehozva és aktiválva: /swapfile
[OK]   /swapfile hozzáadva az /etc/fstab-hoz

2/2 Rendszerparaméterek finomhangolása

[?] Alkalmazzuk a sysctl optimalizációkat? [Y/n]: y
Rendszerparaméterek finomhangolása (sysctl)

[OK]   Eredeti sysctl értékek mentve: /var/backups/swap_optimalizalo/sysctl_backup_20260809_153000.conf

[OK]     vm.swappiness                            60 → 10
[OK]     vm.vfs_cache_pressure                    100 → 50
[OK]     vm.dirty_ratio                           20 → 10
[OK]     vm.dirty_background_ratio                10 → 5

[OK]   sysctl -p alkalmazása...

═══ KÉSZ ═══

  Swap fájl:     /swapfile (2.0 GB)
  Swap összesen: 2.0 GB

  Aktív swap-ok:
  NAME      TYPE  SIZE USED PRIO
  /swapfile file    2G   0B   10

  Naplófájl:     /var/log/swap_optimalizalo.log
```

---

## 🔄 Visszaállítás

Ha bármilyen probléma adódna, a módosítások visszaállíthatók:

```bash
# sysctl értékek visszaállítása
sudo ./swap_optimalizalo.sh --rollback

# Swap fájl eltávolítása
sudo ./swap_optimalizalo.sh --remove-swap
```

A biztonsági mentések a `/var/backups/swap_optimalizalo/` könyvtárban találhatók.
A rollback csak a script által kezelt 4 sysctl kulcsot állítja vissza.

---

## ⚠️ Fontos

- **Első futtatás előtt mindig használd a `--dry-run` kapcsolót**, hogy lásd, milyen változtatásokat fog végezni a script
- A swap fájl létrehozása lemezterületet foglal — győződj meg róla, hogy van elég szabad hely a megadott elérési úton
- A sysctl módosítások azonnal életbe lépnek és **reboot után is megmaradnak** (`/etc/sysctl.conf`-ba írva)
- Ha a rendszeren a `/swapfile`-on kívül más swap is aktív, a script **nem bántja** azokat

---

## 🗂️ Fájlok

| Fájl | Leírás |
|------|--------|
| `/swapfile` | A létrehozott swap fájl (alapértelmezett hely) |
| `/etc/fstab` | Swap bejegyzés hozzáadva (boot után automatikus aktiválás) |
| `/etc/sysctl.conf` | Optimalizált rendszerparaméterek (4 memória kulcs) |
| `/var/log/swap_optimalizalo.log` | Részletes műveleti napló |
| `/var/backups/swap_optimalizalo/` | Biztonsági mentések könyvtára |

---

## ❤️ Készítette: Doky  
📅 2026.08.09
