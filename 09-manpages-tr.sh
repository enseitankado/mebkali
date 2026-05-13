#!/usr/bin/env bash
# 09-manpages-tr.sh
# Türkçe manpages + `yardim` komutu (tldr → man tr → man fallback).
# Sınıfta İngilizce komut yardımı yerine Türkçe açıklama göster.
#
# Çalıştırma: sudo bash 09-manpages-tr.sh
# Geri alma: sudo bash 09-manpages-tr.sh --revert

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-apply}"
YARDIM="/usr/local/bin/yardim"
TLDR_CACHE_DIR="/var/cache/mebkali/tldr-tr"

# Apt timeout + ilerleme göstergesi — donmuş gibi durmasın
APT_OPTS=(
  -o Acquire::http::Timeout=15
  -o Acquire::https::Timeout=15
  -o Acquire::Retries=1
  -o DPkg::Lock::Timeout=30
)
# apt_install_progress <paket> [<timeout-sn>]
# Arka planda kurar; her 3 sn'de "geçti" satırı basar; timeout aşılırsa öldürür.
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
      printf "  ${YELLOW}[!]${NC} %s kurulumu %ds zaman aşımına uğradı — atlanıyor\n" "$pkg" "$tmo"
      tail -3 "$logf" 2>/dev/null | sed 's/^/      ┄ /'
      rm -f "$logf"
      return 124
    fi
  done
  wait "$pid"; local rc=$?
  if [[ $rc -eq 0 ]]; then
    printf "  ${GREEN}[+]${NC} %s kuruldu (%ds)\n" "$pkg" "$t"
  else
    printf "  ${YELLOW}[!]${NC} %s kurulamadı (rc=%d) — atlanıyor\n" "$pkg" "$rc"
    tail -3 "$logf" 2>/dev/null | sed 's/^/      ┄ /'
  fi
  rm -f "$logf"
  return $rc
}

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma..."
  rm -f "$YARDIM"
  rm -rf "$TLDR_CACHE_DIR"
  ok "yardim komutu kaldırıldı (manpages-tr paketi kalır — apt remove ile silinebilir)"
  exit 0
fi

# 1) manpages-tr paketi
say "1/3 Türkçe manpages paketi..."
if dpkg -l manpages-tr 2>/dev/null | grep -q '^ii'; then
  ok "manpages-tr zaten kurulu"
else
  apt_install_progress manpages-tr 60 || true
fi

# 2) tldr (komut başına 1-2 satır pratik örnek; Türkçe çeviri destekli)
say "2/3 tldr (hızlı komut özetleri)..."
if command -v tldr >/dev/null 2>&1; then
  ok "tldr zaten kurulu"
else
  apt_install_progress tldr 60 || true
fi

# tldr Türkçe veritabanını sistem-wide doldur (kullanıcı başına değil)
if command -v tldr >/dev/null 2>&1; then
  mkdir -p "$TLDR_CACHE_DIR"
  # tldr-c (Kali default) farklı, tldr.sh ve tealdeer farklı sözdizimi.
  # En tutarlısı: LANG=tr_TR ile çalıştırma; cache user-bazlı oluşur.
  # Burada sadece dizini hazır ediyoruz; ilk yardim çağrısında tldr -u yapılır.
  ok "tldr cache dizini hazır: $TLDR_CACHE_DIR"
fi

# 3) yardim wrapper
say "3/3 /usr/local/bin/yardim wrapper..."
cat > "$YARDIM" <<'EOF'
#!/usr/bin/env bash
# yardim — Türkçe öncelikli komut yardımı
# Sıra: tldr (tr) → man -L tr → tldr (en) → man → "yardım bulunamadı"
# mebkali tarafından üretildi (09-manpages-tr.sh)

set -uo pipefail

if [[ $# -eq 0 ]]; then
  cat <<MSG
Kullanım: yardim <komut>

Komutla ilgili Türkçe açıklama, örnekler ve manuel sayfayı sırayla dener:
  1. tldr -L tr <komut>        (Türkçe örnek)
  2. man -L tr <komut>          (Türkçe manuel)
  3. tldr <komut>               (İngilizce örnek)
  4. man <komut>                (İngilizce manuel)
  5. <komut> --help             (varsa)

Örnek:  yardim nmap
        yardim ls
MSG
  exit 0
fi

CMD="$1"
shift || true

# Üst başlık
_hl() { printf '\033[1;36m== %s ==\033[0m\n' "$*"; }
_dim() { printf '\033[2m%s\033[0m\n' "$*"; }

FOUND=0

# 1) tldr -L tr
if command -v tldr >/dev/null 2>&1; then
  # tldr farklı dağıtımlarda farklı sözdizimi: -L tr veya --language tr
  if out=$(tldr -L tr "$CMD" 2>/dev/null) && [[ -n "$out" ]] \
     && ! grep -qi 'no tldr entry\|404\|not found\|bulunamadı' <<<"$out"; then
    _hl "tldr (tr) — $CMD"
    printf '%s\n\n' "$out"
    FOUND=1
  fi
fi

# 2) man -L tr
if man -L tr -w "$CMD" >/dev/null 2>&1; then
  _hl "man -L tr — $CMD"
  exec man -L tr "$CMD"
fi

# 3) tldr (ingilizce)
if (( FOUND == 0 )) && command -v tldr >/dev/null 2>&1; then
  if out=$(tldr "$CMD" 2>/dev/null) && [[ -n "$out" ]] \
     && ! grep -qi 'no tldr entry\|404\|not found' <<<"$out"; then
    _hl "tldr (en) — $CMD"
    printf '%s\n\n' "$out"
    _dim "(Türkçe çevirisi yok — İngilizce gösterildi)"
    FOUND=1
  fi
fi

# 4) man (ingilizce)
if man -w "$CMD" >/dev/null 2>&1; then
  if (( FOUND == 1 )); then
    _dim "Detay için: man $CMD"
  else
    _hl "man — $CMD"
    exec man "$CMD"
  fi
  exit 0
fi

# 5) --help
if (( FOUND == 0 )); then
  if command -v "$CMD" >/dev/null 2>&1; then
    _hl "$CMD --help"
    "$CMD" --help 2>&1 | head -80
    exit 0
  fi
  printf '\033[31mYardım bulunamadı:\033[0m %s\n' "$CMD"
  printf 'Öneriler:\n'
  printf '  apropos %s         # konuyla ilgili man sayfalarını ara\n' "$CMD"
  printf '  command -v %s      # komut PATH üzerinde mi?\n' "$CMD"
  exit 1
fi
EOF
chmod 0755 "$YARDIM"
ok "$YARDIM yazıldı"

# tldr veritabanını ilk açılışta otomatik güncellesin (root, sistem genelinde mümkün değil)
# Bunun yerine: kullanıcı `yardim` ilk çağırdığında tldr cache kendi oluşturulur.

echo
ok "Türkçe yardım sistemi kuruldu."
echo "  Deneme: yardim nmap"
echo "  Deneme: yardim ls"
echo "  Deneme: yardim mkdir"
