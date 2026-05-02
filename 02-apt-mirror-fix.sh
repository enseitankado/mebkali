#!/usr/bin/env bash
# 02-apt-mirror-fix.sh
# Apt mirror'ını test edip çalışan ilk yedeğe geçirir; başarısız olursa rollback.
# Çalıştırma: sudo bash 02-apt-mirror-fix.sh
#
# Akış:
#   1. /etc/apt/sources.list'teki mevcut mirror'ı tespit eder
#   2. Onu test eder + apt-get update dener — başarılıysa çıkar (idempotent)
#   3. Başarısızsa CANDIDATES listesini sırayla test eder (HTTPS InRelease HEAD)
#   4. İlk 200 dönen mirror'ı sources.list'e yazar (zaman damgalı yedekle)
#   5. apt-get update ile doğrular; başarısız olursa eski sources.list'e revert eder
#   6. Hiç çalışan mirror yoksa rollback edip exit 1
#
# /etc/apt/sources.list.d/ altındaki dosyalar dokunulmaz (3rd party PPA'lar).

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

SOURCES_LIST="/etc/apt/sources.list"
SUITE="kali-rolling"
CONNECT_TIMEOUT=8
TOTAL_TIMEOUT=12

# Aday mirror listesi - öncelik sırasıyla. Liste zamanla bayatlayabilir;
# script HER mirror'ı çalıştırıldığı anda test edip ilk geçeni seçer.
# https tercih edilir; en sonda http fallback.
CANDIDATES=(
  "https://kali.download/kali"                  # Resmi CDN (varsayılan, en hızlı)
  "https://kali.mirror.garr.it/mirrors/kali"    # GARR İtalya (üniversite)
  "https://mirror.netcologne.de/kali"           # NetCologne Almanya
  "https://archive-1.kali.org/kali"             # Resmi arşiv 1
  "https://archive-2.kali.org/kali"             # Resmi arşiv 2
  "https://archive-3.kali.org/kali"             # Resmi arşiv 3
  "https://mirror.its.dal.ca/kali"              # Dalhousie Üni Kanada
  "https://ftp.harukasan.org/kali"              # KAIST Kore
  "https://mirror.zedat.fu-berlin.de/kali"      # FU Berlin
  "https://http.kali.org/kali"                  # http.kali.org (https üzerinden)
  "http://http.kali.org/kali"                   # Son çare: http
)

# test_mirror <url> — InRelease 200 ise 0, değilse non-zero
test_mirror() {
  local url="$1"
  local code
  code="$(curl -sLo /dev/null \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$TOTAL_TIMEOUT" \
                "${url%/}/dists/${SUITE}/InRelease" \
                -w "%{http_code}" 2>/dev/null || echo "000")"
  [[ "$code" == "200" ]]
}

# current_mirror — sources.list'teki kali-rolling deb satırından URL'yi çıkarır
current_mirror() {
  awk '
    /^[[:space:]]*deb([-]src)?[[:space:]]/ && /'"$SUITE"'/ && !/^[[:space:]]*#/ {
      for (i=2; i<=NF; i++) {
        if ($i ~ /^https?:\/\//) { print $i; exit }
      }
    }
  ' "$SOURCES_LIST"
}

apt_update_ok() {
  # Çıktı canlı akar (her satır anında stderr'e); aynı zamanda log'a
  # yazılır ki sonra hata grep'leyebilelim. tail kullanmıyoruz çünkü
  # tail tüm girdiyi bekliyor ve kullanıcı askıda kalmış gibi görünüyor.
  local logf rc
  logf="$(mktemp)"
  say "apt-get update çalıştırılıyor (Kali rolling deposu büyük; 30-90 sn sürebilir)..."
  apt-get update 2>&1 | tee "$logf" >&2
  rc=${PIPESTATUS[0]}
  if (( rc != 0 )); then rm -f "$logf"; return 1; fi
  if grep -qE "^(Err|E:|W: Failed to fetch)" "$logf"; then
    rm -f "$logf"; return 1
  fi
  rm -f "$logf"
  return 0
}

# 1) Mevcut durumu oku
[[ -f "$SOURCES_LIST" ]] || { err "$SOURCES_LIST yok"; exit 1; }
CURRENT="$(current_mirror)"
[[ -n "$CURRENT" ]] && say "Mevcut mirror: $CURRENT" || warn "sources.list'te kali-rolling satırı bulunamadı"

# 2) Mevcut çalışıyorsa dokunma
if [[ -n "$CURRENT" ]] && test_mirror "$CURRENT"; then
  ok "Mevcut mirror InRelease testini geçti"
  if apt_update_ok; then
    ok "apt-get update sorunsuz - değişiklik gerekmiyor"
    exit 0
  else
    warn "InRelease 200 ama apt-get update'te hata var; mirror değiştirilecek"
  fi
else
  [[ -n "$CURRENT" ]] && warn "Mevcut mirror erişilemez"
fi

# 3) Adayları sırayla test et
say "Aday mirror'lar test ediliyor..."
WORKING=""
for url in "${CANDIDATES[@]}"; do
  printf "    %-50s " "$url"
  if test_mirror "$url"; then
    printf "%sOK%s\n" "$GREEN" "$NC"
    WORKING="$url"
    break
  else
    printf "%sFAIL%s\n" "$RED" "$NC"
  fi
done

if [[ -z "$WORKING" ]]; then
  err "Hiç çalışan mirror bulunamadı. CANDIDATES listesini güncelleyip tekrar dene."
  exit 1
fi
ok "Seçilen mirror: $WORKING"

# 4) Yedek + sources.list rewrite
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${SOURCES_LIST}.bak.${TS}"
cp -a "$SOURCES_LIST" "$BACKUP"
ok "Yedek alındı: $BACKUP"

# Sadece kali-rolling içeren deb/deb-src satırlarındaki URL'yi değiştir.
# Yorum satırlarına dokunma. [signed-by=...] gibi options'ları koru.
# awk ile field-bazlı: ilk http(s) tokeni değiştir.
TMP="$(mktemp)"
awk -v new="$WORKING" -v suite="$SUITE" '
  # Yorum veya boş satırları olduğu gibi geçir
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
  # deb veya deb-src ile başlayan ve suite (kali-rolling) içeren satırlar
  $1 == "deb" || $1 == "deb-src" {
    if ($0 ~ "[[:space:]]" suite "([[:space:]]|$)") {
      for (i=2; i<=NF; i++) {
        if ($i ~ /^https?:\/\//) {
          $i = new
          break
        }
      }
    }
    print
    next
  }
  { print }
' "$SOURCES_LIST" > "$TMP"

if ! diff -q "$SOURCES_LIST" "$TMP" >/dev/null 2>&1; then
  install -m 0644 -o root -g root "$TMP" "$SOURCES_LIST"
  ok "sources.list güncellendi:"
  diff "$BACKUP" "$SOURCES_LIST" | sed 's/^/    /' || true
else
  warn "sources.list değişmedi (mevcut URL zaten seçilen mirror'a eşit)"
fi
rm -f "$TMP"

# 5) apt-get update ile doğrula; başarısızsa revert
say "apt-get update doğrulama..."
if apt_update_ok; then
  ok "apt-get update başarılı: $WORKING"
  ok "İşlem tamam. Yedek korundu: $BACKUP"
  exit 0
else
  err "apt-get update başarısız; eski sources.list'e revert ediliyor"
  cp -a "$BACKUP" "$SOURCES_LIST"
  warn "Revert edildi. CANDIDATES listesinden başka mirror denemek için betiği yeniden çalıştırın."
  exit 1
fi
