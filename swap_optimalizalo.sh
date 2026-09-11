#!/usr/bin/env bash
# =============================================================================
# Swap Optimalizáló Script - Ubuntu/Debian
# Készítette: Doky | 2026.08.09
# =============================================================================
set -euo pipefail

# --- Konfigurációs konstansok ------------------------------------------------
DEFAULT_SWAP_FILE="/swapfile"
SWAP_PRIORITY=10
# Kézi --swap-size minimuma (MB). Az automatikus méretezést NEM érinti.
MIN_SWAP_SIZE_MB=512

# Swappiness: minél kisebb, annál kevésbé swap-el a kernel
VM_SWAPPINESS=10

BACKUP_DIR="/var/backups/swap_optimalizalo"
LOG_FILE="/var/log/swap_optimalizalo.log"

# --- Színkódok ---------------------------------------------------------------
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"

# --- Log & kimenet függvények ------------------------------------------------
log_msg() {
    # Dry-run módban semmit nem írunk a lemezre
    [[ "$DRY_RUN" == "true" ]] && return 0
    local level="$1" msg="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # Ha a napló nem írható (pl. nem root futtatás), csendben kihagyjuk
    if [[ -e "$LOG_FILE" && ! -w "$LOG_FILE" ]] || [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        return 0
    fi
    printf "%s [%s] %s\n" "$timestamp" "$level" "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()    { local fmt="$1"; shift; printf "${C_BLUE}[INFO]${C_RESET} ${fmt}\n" "$@"; log_msg "INFO" "$(printf "$fmt" "$@")"; }
success() { local fmt="$1"; shift; printf "${C_GREEN}[OK]${C_RESET}   ${fmt}\n" "$@"; log_msg "OK" "$(printf "$fmt" "$@")"; }
warn()    { local fmt="$1"; shift; printf "${C_YELLOW}[WARN]${C_RESET} ${fmt}\n" "$@" >&2; log_msg "WARN" "$(printf "$fmt" "$@")"; }
err()     { local fmt="$1"; shift; printf "${C_RED}[ERROR]${C_RESET} ${fmt}\n" "$@" >&2; log_msg "ERROR" "$(printf "$fmt" "$@")"; }
banner()  { printf "${C_CYAN}${C_BOLD}%s${C_RESET}\n" "$*"; }

_center_box() {
    local text="$1" box_width="${2:-52}"
    local inner=$((box_width - 2))

    local text_width
    text_width=$(printf "%s" "$text" | wc -L)

    local total_pad=$((inner - text_width))
    local left=$((total_pad / 2))
    local right=$((total_pad - left))

    local bar
    printf -v bar '%*s' "$inner" ''
    bar="${bar// /═}"

    banner "╔${bar}╗"
    printf "${C_CYAN}${C_BOLD}║%*s%s%*s║${C_RESET}\n" "$left" '' "$text" "$right" ''
    banner "╚${bar}╝"
}

die() {
    err "$@"
    exit 1
}

# --- Segédfüggvények ---------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "A scriptet root jogosultsággal kell futtatni! (sudo ./swap_optimalizalo.sh)"
    fi
}

get_ram_mb() {
    local meminfo_kb
    meminfo_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    printf "%d" "$((meminfo_kb / 1024))"
}

get_current_swap_mb() {
    local swap_total_kb
    swap_total_kb="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
    printf "%d" "$((swap_total_kb / 1024))"
}

calc_swap_size_mb() {
    local ram_mb="$1"
    local swap_mb

    # VPS-barát méretezés:
    #   ≤ 4 GB RAM      → 2 GB swap
    #   5-63 GB RAM     → 4 GB swap
    #   ≥ 64 GB RAM     → 8 GB swap
    if [[ $ram_mb -le 4096 ]]; then
        swap_mb=2048
    elif [[ $ram_mb -lt 65536 ]]; then
        swap_mb=4096
    else
        swap_mb=8192
    fi
    printf "%d" "$swap_mb"
}

human_size() {
    local mb="$1"
    if [[ $mb -ge 1024 ]]; then
        printf "%.1f GB" "$(awk "BEGIN {printf \"%.1f\", $mb/1024}")"
    else
        printf "%d MB" "$mb"
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn

    if [[ "$NO_INTERACTIVE" == "true" ]]; then
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        read -r -p "$(printf "${C_CYAN}[?]${C_RESET} ${prompt} [Y/n]: ")" yn
        yn="${yn:-y}"
    else
        read -r -p "$(printf "${C_CYAN}[?]${C_RESET} ${prompt} [y/N]: ")" yn
        yn="${yn:-n}"
    fi

    [[ "$yn" =~ ^[Yy]$ ]]
}

# --- Rendszerinformációk megjelenítése ---------------------------------------
show_system_info() {
    local ram_mb swap_mb
    ram_mb="$(get_ram_mb)"
    swap_mb="$(get_current_swap_mb)"

    _center_box "Swap Optimalizáló"
    printf "\n"
    printf "  ${C_BOLD}Rendszerinformációk:${C_RESET}\n"
    printf "  ─────────────────────────────────────────────\n"
    printf "  Kernel:        ${C_CYAN}%s${C_RESET}\n" "$(uname -r)"
    printf "  Disztribúció:  ${C_CYAN}%s${C_RESET}\n" "$(lsb_release -ds 2>/dev/null || awk -F'"' '/^PRETTY_NAME/ {print $2}' /etc/os-release 2>/dev/null || echo 'Ismeretlen')"
    printf "  RAM:           ${C_GREEN}%s${C_RESET}\n" "$(human_size "$ram_mb")"
    printf "  Jelenlegi swap:${C_YELLOW}%s${C_RESET}\n" "$(human_size "$swap_mb")"
    printf "  Lemez szabad:  ${C_GREEN}%s${C_RESET}\n" "$(df -h / | awk 'NR==2 {print $4}')"
    printf "\n"

    # Aktív swap-ok listázása + több swap figyelmeztetés
    local other_swaps
    other_swaps="$(swapon --show 2>/dev/null | awk -v f="$SWAP_FILE" 'NR > 1 && $1 != f {print $1}' || true)"
    if [[ -n "$other_swaps" ]]; then
        warn "A rendszeren több swap is aktív:"
        while IFS= read -r sw; do
            printf "      - ${C_YELLOW}%s${C_RESET}\n" "$sw"
        done <<< "$other_swaps"
        info "A script csak a saját fájlját kezeli (%s), a többi swaphoz nem nyúl." "$SWAP_FILE"
        printf "\n"
    fi

    # Ajánlott swap méret
    local recommended
    recommended="$(calc_swap_size_mb "$ram_mb")"
    if [[ "$swap_mb" -gt 0 ]]; then
        printf "  ${C_BOLD}Swap méret ajánlás:${C_RESET}\n"
        printf "  Jelenlegi: %-10s → Ajánlott: ${C_GREEN}%s${C_RESET}\n" \
            "$(human_size "$swap_mb")" "$(human_size "$recommended")"
    fi
    printf "\n"
}

# --- Sysctl segédfüggvények --------------------------------------------------
_sctl_should_apply() {
    local direction="$1" current="$2" target="$3"
    case "$direction" in
        max) [[ $current -gt $target ]] ;;  # lower is better: apply only if current > target
        *)   return 0 ;;
    esac
}

apply_sysctl_value() {
    local key="$1" val="$2" direction="${3:-set}"
    local current
    current="$(sysctl -n "$key" 2>/dev/null || echo 'N/A')"

    if [[ $current =~ ^[0-9]+$ ]] && [[ $val =~ ^[0-9]+$ ]]; then
        if ! _sctl_should_apply "$direction" "$current" "$val"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                printf "  ${C_CYAN}[DRY-RUN]${C_RESET} %-40s %s (már optimális, kihagyva)\n" "$key" "$current"
            else
                info "  %-40s %s (már optimális, kihagyva)" "$key" "$current"
            fi
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} %-40s %s → %s\n" "$key" "$current" "$val"
        return 0
    fi

    if sysctl -w "$key=$val" &>/dev/null; then
        success "  %-40s %s → %s" "$key" "$current" "$val"
    else
        warn "  %-40s nem sikerült beállítani (jelenleg: %s)" "$key" "$current"
    fi
}

persist_sysctl_value() {
    local key="$1" val="$2"
    local esc_key pattern
    esc_key="${key//./\.}"
    pattern="^[[:space:]]*${esc_key}[[:space:]]*="

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} ${key}=${val} → /etc/sysctl.conf\n"
        return 0
    fi

    if grep -q "$pattern" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s|${pattern}.*|${key} = ${val}|" /etc/sysctl.conf
    else
        printf "%s = %s\n" "$key" "$val" >> /etc/sysctl.conf
    fi
}

apply_sysctl_all() {
    banner "Rendszerparaméterek finomhangolása (sysctl)"
    printf "\n"

    # max = lower is better, futásidőben csak akkor állítjuk ha a jelenlegi > cél.
    # A perzisztencia MINDIG lefut, hogy reboot után is a kívánt érték legyen érvényben.
    apply_sysctl_value vm.swappiness "$VM_SWAPPINESS" max
    persist_sysctl_value vm.swappiness "$VM_SWAPPINESS"

    printf "\n"
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} sysctl -p (újratöltés)\n"
    else
        success "sysctl -p alkalmazása..."
        sysctl -p &>/dev/null || true
    fi
}

# --- Swap fájl műveletek -----------------------------------------------------
_regex_escape() {
    # Minden karaktert literálként kezelünk (BRE-kompatibilis, GNU grep/sed alatt is)
    printf '%s' "$1" | sed 's/[^^]/[&]/g; s/\^/\\^/g'
}

deactivate_existing_swapfile() {
    local swapfile="$1"
    if swapon --show | awk -v f="$swapfile" '$1 == f {found=1} END {exit !found}'; then
        if [[ "$DRY_RUN" == "true" ]]; then
            printf "  ${C_CYAN}[DRY-RUN]${C_RESET} swapoff %s\n" "$swapfile"
            return 0
        fi
        if swapoff "$swapfile" 2>/dev/null; then
            success "Meglévő swap fájl lekapcsolva: %s" "$swapfile"
        else
            warn "A meglévő swap fájl lekapcsolása nem sikerült: %s" "$swapfile"
            return 1
        fi
    fi
    return 0
}

_is_swap_active() {
    local swapfile="$1"
    swapon --show 2>/dev/null | awk -v f="$swapfile" '$1 == f {found=1} END {exit !found}'
}

_get_file_size_mb() {
    local file="$1"
    printf "%d" "$(( $(stat -c%s "$file" 2>/dev/null || echo 0) / 1048576 ))"
}

create_swap_file() {
    local swapfile="$1" size_mb="$2"
    local current_size_mb=0

    # --- Meglévő fájl kezelése: egyetlen konzisztens folyamat ---
    if [[ -f "$swapfile" ]]; then
        current_size_mb="$(_get_file_size_mb "$swapfile")"

        # 1. Megfelelő méret → nem cserélünk feleslegesen
        if [[ "$current_size_mb" -eq "$size_mb" ]]; then
            info "A swap fájl már megfelelő méretű (%s), csere nem szükséges." "$(human_size "$size_mb")"
            if ! _is_swap_active "$swapfile"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    printf "  ${C_CYAN}[DRY-RUN]${C_RESET} A swap fájl inaktív, aktiválnánk: swapon --priority %d %s\n" "$SWAP_PRIORITY" "$swapfile"
                    return 0
                fi
                if swapon --priority "$SWAP_PRIORITY" "$swapfile"; then
                    success "A meglévő swap fájl aktiválva: %s" "$swapfile"
                else
                    warn "A meglévő swap fájl aktiválása nem sikerült: %s" "$swapfile"
                    return 1
                fi
            else
                info "A swap fájl aktív, minden rendben."
            fi
            return 0
        fi

        # 2. Eltérő méret → csak ekkor kérdezünk / cserélünk
        warn "A swap fájl mérete eltér: jelenlegi %s, kívánt %s" \
            "$(human_size "$current_size_mb")" "$(human_size "$size_mb")"
        if [[ "$DRY_RUN" == "true" ]]; then
            printf "  ${C_CYAN}[DRY-RUN]${C_RESET} Lecserélnénk a meglévő fájlt: swapoff → rm → új létrehozás\n"
        elif ! confirm "Lecseréljük a meglévő fájlt?" "n"; then
            info "A meglévő swap fájl változatlan marad (nem lett lekapcsolva)."
            return 1
        fi

        # 3. Jóváhagyás után: biztonságos swapoff, majd törlés (csak élő módban)
        if [[ "$DRY_RUN" != "true" ]]; then
            if ! deactivate_existing_swapfile "$swapfile"; then
                die "A meglévő swap fájl lekapcsolása nem sikerült: %s" "$swapfile"
            fi
            rm -f "$swapfile"
        fi
    fi

    # --- Új fájl létrehozása ---
    info "Swap fájl létrehozása: %s (%s)..." "$swapfile" "$(human_size "$size_mb")"

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} fallocate -l %sM %s\n" "$size_mb" "$swapfile"
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} chmod 600 %s\n" "$swapfile"
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} mkswap %s\n" "$swapfile"
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} swapon --priority %d %s\n" "$SWAP_PRIORITY" "$swapfile"
        return 0
    fi

    # Fájl létrehozása
    if command -v fallocate &>/dev/null; then
        if ! fallocate -l "${size_mb}M" "$swapfile"; then
            warn "fallocate sikertelen, dd-vel próbálkozunk..."
            if ! dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" status=progress; then
                die "dd-vel sem sikerült a swap fájl létrehozása: %s" "$swapfile"
            fi
        fi
    else
        if ! dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" status=progress; then
            die "A swap fájl létrehozása nem sikerült: %s" "$swapfile"
        fi
    fi

    chmod 600 "$swapfile"
    mkswap "$swapfile"
    if ! swapon --priority "$SWAP_PRIORITY" "$swapfile"; then
        die "Az új swap fájl aktiválása nem sikerült: %s" "$swapfile"
    fi
    success "Swap fájl létrehozva és aktiválva: %s" "$swapfile"
}

update_fstab() {
    local swapfile="$1" esc_file
    esc_file="$(_regex_escape "$swapfile")"

    # Ellenőrizzük, hogy már szerepel-e a fstab-ban
    if grep -q "^[^#]*${esc_file}[[:space:]]" /etc/fstab 2>/dev/null; then
        info "%s már szerepel az /etc/fstab-ban, kihagyás." "$swapfile"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} %-30s none swap sw,pri=%d 0 0 → /etc/fstab\n" "$swapfile" "$SWAP_PRIORITY"
        return 0
    fi

    cp /etc/fstab "$BACKUP_DIR/fstab.bak_$(date +%Y%m%d_%H%M%S)"
    printf "%-30s none swap sw,pri=%d 0 0\n" "$swapfile" "$SWAP_PRIORITY" >> /etc/fstab
    success "%s hozzáadva az /etc/fstab-hoz" "$swapfile"
}

# --- Swap eltávolítás ---------------------------------------------------------
remove_swap() {
    local esc_file
    esc_file="$(_regex_escape "$SWAP_FILE")"

    if [[ "$DRY_RUN" == "true" ]]; then
        if swapon --show | awk -v f="$SWAP_FILE" '$1 == f {found=1} END {exit !found}'; then
            printf "  ${C_CYAN}[DRY-RUN]${C_RESET} swapoff %s\n" "$SWAP_FILE"
        fi
        if [[ -f "$SWAP_FILE" ]]; then
            printf "  ${C_CYAN}[DRY-RUN]${C_RESET} rm %s\n" "$SWAP_FILE"
        fi
        printf "  ${C_CYAN}[DRY-RUN]${C_RESET} %s bejegyzés törölve az /etc/fstab-ból\n" "$SWAP_FILE"
        return 0
    fi

    if swapon --show 2>/dev/null | awk -v f="$SWAP_FILE" '$1 == f {found=1} END {exit !found}'; then
        if swapoff "$SWAP_FILE"; then
            success "Swap fájl lekapcsolva: %s" "$SWAP_FILE"
        else
            warn "Swap fájl lekapcsolása nem sikerült: %s" "$SWAP_FILE"
            return 1
        fi
    else
        info "A swap fájl nincs aktív: %s" "$SWAP_FILE"
    fi

    if [[ -f "$SWAP_FILE" ]]; then
        rm -f "$SWAP_FILE"
        success "Swap fájl törölve: %s" "$SWAP_FILE"
    else
        info "A swap fájl nem található: %s" "$SWAP_FILE"
    fi

    if grep -q "^[^#]*${esc_file}[[:space:]]" /etc/fstab 2>/dev/null; then
        cp /etc/fstab "$BACKUP_DIR/fstab.bak_$(date +%Y%m%d_%H%M%S)"
        sed -i "\|^[^#]*${esc_file}[[:space:]]|d" /etc/fstab
        success "%s bejegyzés törölve az /etc/fstab-ból" "$SWAP_FILE"
    else
        info "%s nem található az /etc/fstab-ban" "$SWAP_FILE"
    fi
}

# --- Dry-run összefoglaló ----------------------------------------------------
dry_run_summary() {
    local ram_mb swap_mb recommended
    ram_mb="$(get_ram_mb)"
    swap_mb="$(get_current_swap_mb)"
    recommended="$(calc_swap_size_mb "$ram_mb")"

    printf "\n"
    banner "═══ ÖSSZEFOGLALÓ (Dry-Run) ═══"
    printf "\n"
    printf "  ${C_BOLD}Swap műveletek:${C_RESET}\n"
    printf "  ─────────────────\n"
    printf "  Swap fájl:      ${C_CYAN}%s${C_RESET}\n" "$SWAP_FILE"
    printf "  Méret:          ${C_GREEN}%s${C_RESET}\n" "$(human_size "$SWAP_SIZE_MB")"
    printf "  Jelenlegi swap: %s\n" "$(human_size "$swap_mb")"
    if [[ -f "$SWAP_FILE" ]]; then
        local existing_size
        existing_size="$(_get_file_size_mb "$SWAP_FILE")"
        if [[ "$existing_size" -eq "$SWAP_SIZE_MB" ]]; then
            printf "  ${C_GREEN}A meglévő fájl mérete megfelelő, csere nem szükséges.${C_RESET}\n"
        else
            printf "  ${C_YELLOW}A meglévő fájl (%s) eltérő méretű – normál futásban lecserélve lenne.${C_RESET}\n" "$(human_size "$existing_size")"
        fi
    fi
    printf "\n"

    if [[ "$NO_TUNE" != "true" ]]; then
        printf "  ${C_BOLD}sysctl finomhangolás:${C_RESET}\n"
        printf "  ───────────────────────\n"
        printf "  vm.swappiness                 → %s\n" "$VM_SWAPPINESS"
        printf "\n"
    fi

    banner "═══ A '--dry-run' miatt NEM történt módosítás ═══"
}

# --- Súgó --------------------------------------------------------------------
show_help() {
    cat << 'EOF'
Swap Optimalizáló Script - Ubuntu/Debian
====================================================

Használat: sudo ./swap_optimalizalo.sh [OPCIÓK]

Opciók:
  --dry-run              Csak szimuláció, nem módosít semmit
  --swap-size <MB>       Swap fájl méretének kézi megadása MB-ban (min. 512)
  --swap-file <PATH>     Swap fájl elérési útja (alapértelmezett: /swapfile)
  --no-tune              Csak swap fájl létrehozása, sysctl finomhangolás nélkül
  --remove-swap         Swap fájl + /etc/fstab bejegyzés eltávolítása
  --force, -y            Interaktív megerősítések átugrása (automatikus mód)
  --help                 Ez a súgó

Példák:
  sudo ./swap_optimalizalo.sh --dry-run        # Csak előnézet
  sudo ./swap_optimalizalo.sh                  # Interaktív mód
  sudo ./swap_optimalizalo.sh --force          # Automatikus futtatás
  sudo ./swap_optimalizalo.sh --swap-size 8192 # 8 GB swap fájl
  sudo ./swap_optimalizalo.sh --remove-swap    # Swap fájl eltávolítása

Swap méretezési logika (automatikus, ha nincs --swap-size):
  RAM ≤ 4 GB      → 2 GB swap
  RAM 5-63 GB     → 4 GB swap
  RAM ≥ 64 GB     → 8 GB swap

Sysctl optimalizáció (csak swap-fókusz):
  vm.swappiness              → 10
EOF
}

# --- Fő folyamat -------------------------------------------------------------
main() {
    # Alapértelmezések
    DRY_RUN="false"
    SWAP_SIZE_MB=""
    SWAP_FILE="$DEFAULT_SWAP_FILE"
    NO_TUNE="false"
    NO_INTERACTIVE="false"
    REMOVE_SWAP="false"

    # CLI paraméterek feldolgozása
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)           DRY_RUN="true"; shift ;;
            --swap-size)         [[ $# -ge 2 ]] || die "A --swap-size opcióhoz érték kell (MB)!"; SWAP_SIZE_MB="$2"; shift 2 ;;
            --swap-file)         [[ $# -ge 2 ]] || die "A --swap-file opcióhoz elérési út kell!"; SWAP_FILE="$2"; shift 2 ;;
            --no-tune)           NO_TUNE="true"; shift ;;
            --remove-swap)       REMOVE_SWAP="true"; shift ;;
            --force|-y)          NO_INTERACTIVE="true"; shift ;;
            --help)              show_help; exit 0 ;;
            *)                   err "Ismeretlen opció: $1"; show_help; exit 1 ;;
        esac
    done

    # Elérési út validálása (fstab/mkswap csak abszolút útvonallal működik megbízhatóan)
    if [[ "$SWAP_FILE" != /* ]]; then
        die "A swap fájl elérési útja abszolút útvonal kell legyen (/-rel kezdődjön): %s" "$SWAP_FILE"
    fi

    check_root

    # Naplózás inicializálása (dry-run módban nem hozunk létre semmit)
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
    fi

    # --remove-swap (különálló művelet, swap fájl + fstab eltávolítása)
    if [[ "$REMOVE_SWAP" == "true" ]]; then
        banner "Swap fájl eltávolítása"
        remove_swap
        exit 0
    fi

    # Rendszer információk
    local ram_mb
    ram_mb="$(get_ram_mb)"

    # Swap méret meghatározása
    if [[ -z "$SWAP_SIZE_MB" ]]; then
        SWAP_SIZE_MB="$(calc_swap_size_mb "$ram_mb")"
    elif [[ ! "$SWAP_SIZE_MB" =~ ^[1-9][0-9]*$ ]]; then
        die "A --swap-size értéke pozitív egész szám (MB) kell legyen, nem: %s" "$SWAP_SIZE_MB"
    elif (( SWAP_SIZE_MB < MIN_SWAP_SIZE_MB )); then
        die "A --swap-size minimum %d MB. Megadott érték: %s" "$MIN_SWAP_SIZE_MB" "$SWAP_SIZE_MB"
    fi

    show_system_info

    # Dry-run: csak összefoglaló és szimuláció
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$NO_TUNE" != "true" ]]; then
            apply_sysctl_all
        fi
        create_swap_file "$SWAP_FILE" "$SWAP_SIZE_MB" || {
            info "A meglévő swap fájl változatlan maradna."
        }
        update_fstab "$SWAP_FILE"
        dry_run_summary
        exit 0
    fi

    # Interaktív megerősítések
    banner "Műveletek megerősítése"
    printf "\n"
    printf "  A következő műveletek kerülnek végrehajtásra:\n"
    printf "    - Swap fájl létrehozása: ${C_CYAN}%s${C_RESET} (${C_GREEN}%s${C_RESET})\n" "$SWAP_FILE" "$(human_size "$SWAP_SIZE_MB")"

    if [[ "$NO_TUNE" != "true" ]]; then
        printf "    - Rendszerparaméterek (sysctl) finomhangolása\n"
    fi
    printf "\n"

    if ! confirm "Folytatjuk a műveleteket?" "n"; then
        info "Megszakítva a felhasználó által."
        exit 0
    fi
    printf "\n"

    # --- Swap fájl létrehozása ---
    banner "1/2 Swap fájl létrehozása"
    printf "\n"
    if ! create_swap_file "$SWAP_FILE" "$SWAP_SIZE_MB"; then
        info "A meglévő swap fájl változatlan marad, folytatás a többi feladattal."
    fi
    update_fstab "$SWAP_FILE"
    printf "\n"

    # --- sysctl finomhangolás ---
    if [[ "$NO_TUNE" != "true" ]]; then
        banner "2/2 Rendszerparaméterek finomhangolása"
        printf "\n"
        apply_sysctl_all
    fi
    printf "\n"

    # --- Végeredmény ---
    banner "═══ KÉSZ ═══"
    printf "\n"
    printf "  Swap fájl:     ${C_GREEN}%s${C_RESET} (%s)\n" "$SWAP_FILE" "$(human_size "$SWAP_SIZE_MB")"
    printf "  Swap összesen: ${C_GREEN}%s${C_RESET}\n" "$(human_size "$(get_current_swap_mb)")"

    local swap_show
    swap_show="$(swapon --show 2>/dev/null || true)"
    if [[ -n "$swap_show" ]]; then
        printf "\n  ${C_BOLD}Aktív swap-ok:${C_RESET}\n"
        while IFS= read -r line; do
            printf "  %s\n" "$line"
        done <<< "$swap_show"
    fi

    printf "\n"
    printf "  Naplófájl:     ${C_CYAN}%s${C_RESET}\n" "$LOG_FILE"
    printf "\n"
}

main "$@"
