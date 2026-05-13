#!/usr/bin/env bash
# 11-servisleri-kapat.sh
# Sınıf VM'i için (4 GB RAM tipik) gereksiz servisleri kapat + VM tuning.
#
# Kapatılanlar (idempotent — yoksa atlanır):
#   cups, cups-browsed        — yazıcı (sınıfta kullanılmaz)
#   bluetooth                  — VM'de bluetooth yok
#   ModemManager               — 3G/4G modem yok
#   avahi-daemon               — mDNS (sınıf ağında istenmez)
#
# Tuning:
#   vm.swappiness=10           — SSD'de swap daha az kullanılsın
#   vm.vfs_cache_pressure=50   — dosya önbelleği daha agresif tutulsun
#   earlyoom                   — Firefox + Burp + msfconsole birlikte açıldığında
#                                kernel OOM donmasından önce ağır süreci öldür
#
# Çalıştırma: sudo bash 11-servisleri-kapat.sh
# Geri alma: sudo bash 11-servisleri-kapat.sh --revert

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-apply}"
SYSCTL="/etc/sysctl.d/99-mebkali-vm.conf"
EARLYOOM_CONF="/etc/default/earlyoom"
SIGN="# mebkali-vm-tuning"

# Apt timeout + ilerleme göstergesi — donmuş gibi durmasın
APT_OPTS=(
  -o Acquire::http::Timeout=15
  -o Acquire::https::Timeout=15
  -o Acquire::Retries=1
  -o DPkg::Lock::Timeout=30
)
apt_install_progress() {
  local pkg="$1" tmo="${2:-60}" logf
  logf="$(mktemp)"
  printf "  ${BLUE}[*]${NC} %s kuruluyor (en fazla %ds)...\n" "$pkg" "$tmo"
  ( env DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" --no-install-recommends "$pkg" >"$logf" 2>&1 ) &
  local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 3; t=$((t+3))
    printf "  ${BLUE}[*]${NC} %s ... %ds geçti%s\n" "$pkg" "$t" \
      "$(tail -1 "$logf" 2>/dev/null | head -c 40 | sed 's/[^[:print:]]//g; s/^/ — /')"
    if (( t >= tmo )); then
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
      printf "  ${YELLOW}[!]${NC} %s kurulumu %ds zaman aşımına uğradı\n" "$pkg" "$tmo"
      rm -f "$logf"; return 124
    fi
  done
  wait "$pid"; local rc=$?
  if [[ $rc -eq 0 ]]; then
    printf "  ${GREEN}[+]${NC} %s kuruldu (%ds)\n" "$pkg" "$t"
  else
    printf "  ${YELLOW}[!]${NC} %s kurulamadı (rc=%d)\n" "$pkg" "$rc"
    tail -3 "$logf" 2>/dev/null | sed 's/^/      ┄ /'
  fi
  rm -f "$logf"; return $rc
}

UNNEEDED=(
  cups
  cups-browsed
  bluetooth
  ModemManager
  avahi-daemon
)
SOCKETS=(
  cups.socket
  avahi-daemon.socket
)

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma..."
  rm -f "$SYSCTL"
  sysctl --system >/dev/null 2>&1 || true
  for s in "${UNNEEDED[@]}"; do
    systemctl unmask "$s" 2>/dev/null || true
    systemctl enable "$s" 2>/dev/null || true
    systemctl start "$s" 2>/dev/null || true
  done
  for s in "${SOCKETS[@]}"; do
    systemctl unmask "$s" 2>/dev/null || true
    systemctl enable "$s" 2>/dev/null || true
  done
  ok "Servisler tekrar etkin + sysctl varsayılana döndü"
  exit 0
fi

# 1) Servisleri durdur + disable + mask (yeniden etkinleşmesin)
say "1/3 Gereksiz servisleri kapat..."
for s in "${UNNEEDED[@]}"; do
  if systemctl list-unit-files "$s.service" 2>/dev/null | grep -q "$s"; then
    state="$(systemctl is-enabled "$s" 2>/dev/null || echo disabled)"
    if [[ "$state" == "masked" ]]; then
      ok "$s zaten masked"
      continue
    fi
    systemctl stop "$s" 2>/dev/null || true
    systemctl disable "$s" 2>/dev/null || true
    systemctl mask "$s" 2>/dev/null || true
    ok "$s durduruldu + masked"
  else
    ok "$s kurulu değil — atlandı"
  fi
done
for s in "${SOCKETS[@]}"; do
  if systemctl list-unit-files "$s" 2>/dev/null | grep -q "$s"; then
    state="$(systemctl is-enabled "$s" 2>/dev/null || echo disabled)"
    if [[ "$state" == "masked" ]]; then
      ok "$s zaten masked"
      continue
    fi
    systemctl stop "$s" 2>/dev/null || true
    systemctl disable "$s" 2>/dev/null || true
    systemctl mask "$s" 2>/dev/null || true
    ok "$s socket masked"
  fi
done

# 2) sysctl: swappiness + cache pressure
say "2/3 sysctl tuning (VM için)..."
if [[ -f "$SYSCTL" ]] && grep -q "$SIGN" "$SYSCTL" 2>/dev/null; then
  ok "sysctl drop-in zaten ayarlı"
else
  cat > "$SYSCTL" <<EOF
$SIGN
# Sınıf VM'i (~4 GB RAM) için bellek davranış tuning
# Swap'a fazla başvurmasın (SSD ömrü + tepkisellik)
vm.swappiness = 10
# Dosya önbelleğini agresif boşaltma — uygulamalar için daha çok RAM
vm.vfs_cache_pressure = 50
# OOM'da en kötü skorlu süreci tek seferde öldür (zincir reaksiyonu yok)
vm.oom_kill_allocating_task = 0
EOF
  chmod 0644 "$SYSCTL"
  sysctl --system >/dev/null 2>&1 || sysctl -p "$SYSCTL" >/dev/null 2>&1 || true
  ok "$SYSCTL yazıldı + uygulandı"
fi

# 3) earlyoom — bellek tükenirken sistem donmasın
say "3/3 earlyoom (Firefox+Burp+msfconsole birlikte açılırsa)..."
if command -v earlyoom >/dev/null 2>&1; then
  ok "earlyoom zaten kurulu"
else
  apt_install_progress earlyoom 60 || true
fi

if command -v earlyoom >/dev/null 2>&1; then
  if ! grep -q "$SIGN" "$EARLYOOM_CONF" 2>/dev/null; then
    # Mevcut yapılandırmayı yedekle (idempotent)
    [[ -f "$EARLYOOM_CONF" ]] && cp -a "$EARLYOOM_CONF" "${EARLYOOM_CONF}.bak.$(date +%Y%m%d)" 2>/dev/null || true
    cat > "$EARLYOOM_CONF" <<EOF
$SIGN
# RAM %10'a, swap %5'e düşünce uyarı; %5 RAM, %2 swap'ta SIGKILL.
# -r 60: her 60sn istatistik logu (journalctl -u earlyoom).
# -p: tüm processler için oom_score artır (Firefox ve msf büyük tüketici, ilk gitsin).
# --avoid: kabuk + login süreçlerini koru (öğrenci çıkmasın).
EARLYOOM_ARGS="-m 10,5 -s 5,2 -r 60 -p --avoid '^(sshd|systemd|Xorg|xfce4-session|lightdm|login)$'"
EOF
    chmod 0644 "$EARLYOOM_CONF"
    systemctl restart earlyoom 2>/dev/null || true
    ok "earlyoom ayarlandı: bellek tükenmek üzereyken kontrollü öldürme"
  else
    ok "earlyoom yapılandırması zaten yerinde"
  fi
  systemctl enable --now earlyoom >/dev/null 2>&1 || true
fi

echo
ok "Servis temizliği + VM tuning tamamlandı."
RAM_FREE="$(free -m | awk '/^Mem:/ {print $7" MB available"}')"
echo "  Şu anki RAM: $RAM_FREE"
warn "Geri almak için: sudo bash $0 --revert"
