#!/usr/bin/env bash
# 10-sinif-kimlik.sh
# Sınıf VM'i için öğrenci kimliği: ilk açılışta ad-soyad / sınıf / dönem sorulur.
# Sonuç:
#   - hostname: s-<isim>-<sinifslug> (ör. s-ahmet-12sg2)
#   - /etc/motd: kimlik bilgisi (terminal açılışında)
#   - /etc/mebkali/kimlik.conf: shell hoşgeldin + conky filigranı bunu okur
#   - ~/.config/mebkali/kimlik.conf: kullanıcı kopyası
#
# Bileşenler:
#   /usr/local/bin/mebkali-kimlik           — kullanıcı için GUI/CLI sorgu
#   /usr/local/sbin/mebkali-kimlik-apply    — root helper (sudoers ile şifresiz)
#   /etc/sudoers.d/mebkali-kimlik           — helper'a şifresiz sudo izni
#   /etc/xdg/autostart/mebkali-kimlik.desktop — ilk girişte otomatik sor
#
# Çalıştırma: sudo bash 10-sinif-kimlik.sh
# Geri alma: sudo bash 10-sinif-kimlik.sh --revert

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-apply}"

KIMLIK_USER="/usr/local/bin/mebkali-kimlik"
KIMLIK_APPLY="/usr/local/sbin/mebkali-kimlik-apply"
SUDOERS="/etc/sudoers.d/mebkali-kimlik"
AUTOSTART="/etc/xdg/autostart/mebkali-kimlik.desktop"
CONF="/etc/mebkali/kimlik.conf"

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma..."
  rm -f "$KIMLIK_USER" "$KIMLIK_APPLY" "$SUDOERS" "$AUTOSTART" "$CONF"
  rm -f "$TARGET_HOME/.config/mebkali/kimlik.conf"
  rm -f /etc/motd
  ok "Kimlik bileşenleri silindi"
  exit 0
fi

mkdir -p /etc/mebkali

# 1) Helper: hostname + /etc/mebkali/kimlik.conf yazıcı (root)
say "1/4 Root helper: $KIMLIK_APPLY"
cat > "$KIMLIK_APPLY" <<'EOF'
#!/usr/bin/env bash
# mebkali-kimlik-apply — root helper.
# Kullanıcıdan veri stdin üzerinden alır (KEY=VALUE satırları):
#   OGRENCI=Ahmet Yılmaz
#   SINIF=12-SG/2
#   DONEM=2025 Güz
# Sonra hostname'i ayarlar, /etc/motd ve /etc/mebkali/kimlik.conf yazar.
set -euo pipefail

OGRENCI=""; SINIF=""; DONEM=""
while IFS='=' read -r k v; do
  case "$k" in
    OGRENCI) OGRENCI="$v" ;;
    SINIF)   SINIF="$v"   ;;
    DONEM)   DONEM="$v"   ;;
  esac
done

# Boş alanlar: helper hiçbir şey yapmaz, sessizce çık
[[ -z "$OGRENCI" || -z "$SINIF" ]] && { echo "Eksik veri" >&2; exit 1; }

# Slugify (TR karakter → ASCII, lowercase, sadece alphanumeric)
slugify() {
  local s="$1"
  s="${s//Ç/c}"; s="${s//ç/c}"
  s="${s//Ğ/g}"; s="${s//ğ/g}"
  s="${s//İ/i}"; s="${s//ı/i}"
  s="${s//Ö/o}"; s="${s//ö/o}"
  s="${s//Ş/s}"; s="${s//ş/s}"
  s="${s//Ü/u}"; s="${s//ü/u}"
  s="${s,,}"
  s="$(printf '%s' "$s" | tr -c 'a-z0-9' ' ' | xargs)"
  s="${s// /}"
  printf '%s' "$s"
}

# İsim: sadece ilk ad
FIRST="${OGRENCI%% *}"
NAME_SLUG="$(slugify "$FIRST")"
CLASS_SLUG="$(slugify "$SINIF")"
HOSTNAME_NEW="s-${NAME_SLUG:-ogrenci}-${CLASS_SLUG:-sinif}"

# hostname
hostnamectl set-hostname "$HOSTNAME_NEW" 2>/dev/null || true
# /etc/hosts içindeki 127.0.1.1 satırını güncelle
if grep -q '^127\.0\.1\.1' /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$HOSTNAME_NEW" >> /etc/hosts
fi

# kimlik.conf
mkdir -p /etc/mebkali
{
  echo "# /etc/mebkali/kimlik.conf — mebkali-kimlik-apply tarafından yazıldı"
  echo "OGRENCI=\"$OGRENCI\""
  echo "SINIF=\"$SINIF\""
  echo "DONEM=\"$DONEM\""
  echo "HOSTNAME=\"$HOSTNAME_NEW\""
  echo "OLUSTURULMA=\"$(date +%Y-%m-%d)\""
} > /etc/mebkali/kimlik.conf
chmod 0644 /etc/mebkali/kimlik.conf

# /etc/motd
cat > /etc/motd <<MOTD

  ┌─ MEBKALI — Kali Eğitim Ortamı ────────────────────────────
  │  Öğrenci : $OGRENCI
  │  Sınıf   : $SINIF
  │  Dönem   : $DONEM
  │  Makine  : $HOSTNAME_NEW
  └────────────────────────────────────────────────────────────
  ⚖  Yetkili eğitim ortamı — Yetkisiz erişim 5237 sayılı TCK 243 kapsamında suçtur.

MOTD

# Conky çalışıyorsa yenile (filigran kimliği anında yansıtsın)
if pgrep -x conky >/dev/null 2>&1; then
  pkill -USR1 conky 2>/dev/null || pkill conky 2>/dev/null || true
  # Conky autostart'tan tekrar başlayacaktır
fi

echo "OK $HOSTNAME_NEW"
EOF
chmod 0755 "$KIMLIK_APPLY"
chown root:root "$KIMLIK_APPLY"
ok "$KIMLIK_APPLY yazıldı"

# 2) Sudoers drop-in: user'a şifresiz erişim ver (sadece bu helper için)
say "2/4 sudoers drop-in: $SUDOERS"
cat > "$SUDOERS" <<EOF
# mebkali-kimlik: helper'ı şifresiz çalıştırma izni (sadece bu binary)
$TARGET_USER ALL=(root) NOPASSWD: $KIMLIK_APPLY
EOF
chmod 0440 "$SUDOERS"
chown root:root "$SUDOERS"
# visudo doğrula
if ! visudo -cf "$SUDOERS" >/dev/null 2>&1; then
  err "Sudoers drop-in geçersiz — siliniyor"
  rm -f "$SUDOERS"
  exit 1
fi
ok "sudoers drop-in geçerli"

# 3) Kullanıcı yüzü: zenity GUI → CLI fallback
say "3/4 Kullanıcı arayüzü: $KIMLIK_USER"
cat > "$KIMLIK_USER" <<'EOF'
#!/usr/bin/env bash
# mebkali-kimlik — sınıf VM'i kimlik kaydı.
# Zenity varsa GUI, yoksa terminalde sorar.
# mebkali tarafından üretildi (10-sinif-kimlik.sh)

set -uo pipefail

CONF="/etc/mebkali/kimlik.conf"
USER_CONF="$HOME/.config/mebkali/kimlik.conf"
APPLY="/usr/local/sbin/mebkali-kimlik-apply"

# --force ile her zaman tekrar sor
FORCE=0
[[ "${1:-}" == "--force" || "${1:-}" == "-f" ]] && FORCE=1

# Zaten kaydedilmişse ve --force değilse: sessizce çık
if [[ -r "$CONF" && $FORCE -eq 0 ]]; then
  exit 0
fi

# Zenity GUI mevcut mu ve DISPLAY var mı?
USE_GUI=0
if [[ -n "${DISPLAY:-}" ]] && command -v zenity >/dev/null 2>&1; then
  USE_GUI=1
fi

if (( USE_GUI )); then
  # Hoşgeldin diyaloğu
  zenity --info \
    --title="MEBKALI — Sınıf Kimliği" \
    --width=400 \
    --text="<b>Bu makinenin kimliği kaydedilecek.</b>\n\nÖğretmen bilgisayar ekranlarına baktığında\nhangi makinenin kime ait olduğunu görmek için.\n\nGirilen bilgiler bu VM'de kalır — ağa gönderilmez." \
    2>/dev/null

  OGRENCI=$(zenity --entry \
    --title="MEBKALI — Kimlik 1/3" \
    --width=400 \
    --text="<b>Ad Soyad</b>\nÖrn: Ahmet Yılmaz" \
    --entry-text="" 2>/dev/null) || exit 0
  [[ -z "$OGRENCI" ]] && { zenity --error --text="Ad-soyad boş bırakılamaz" 2>/dev/null; exit 1; }

  SINIF=$(zenity --entry \
    --title="MEBKALI — Kimlik 2/3" \
    --width=400 \
    --text="<b>Sınıf / Şube</b>\nÖrn: 12-SG/A  veya  10-BLP/3" \
    --entry-text="" 2>/dev/null) || exit 0
  [[ -z "$SINIF" ]] && { zenity --error --text="Sınıf boş bırakılamaz" 2>/dev/null; exit 1; }

  # Dönem: yıl ve güz/bahar otomatik öner
  YEAR=$(date +%Y); MONTH=$(date +%m)
  DEFAULT_TERM="$YEAR Güz"
  [[ "$MONTH" -lt 7 ]] && DEFAULT_TERM="$YEAR Bahar"
  DONEM=$(zenity --entry \
    --title="MEBKALI — Kimlik 3/3" \
    --width=400 \
    --text="<b>Dönem</b>\nÖrn: 2025 Güz, 2026 Bahar" \
    --entry-text="$DEFAULT_TERM" 2>/dev/null) || exit 0
  [[ -z "$DONEM" ]] && DONEM="$DEFAULT_TERM"
else
  # CLI fallback
  echo "MEBKALI — Sınıf Kimliği Kaydı"
  echo "------------------------------"
  read -r -p "Ad Soyad: " OGRENCI
  [[ -z "$OGRENCI" ]] && { echo "Ad-soyad boş." >&2; exit 1; }
  read -r -p "Sınıf/Şube (örn 12-SG/A): " SINIF
  [[ -z "$SINIF" ]] && { echo "Sınıf boş." >&2; exit 1; }
  YEAR=$(date +%Y); MONTH=$(date +%m)
  DEFAULT_TERM="$YEAR Güz"
  [[ "$MONTH" -lt 7 ]] && DEFAULT_TERM="$YEAR Bahar"
  read -r -p "Dönem [$DEFAULT_TERM]: " DONEM
  DONEM="${DONEM:-$DEFAULT_TERM}"
fi

# Helper'a stdin üzerinden ver
TMPDATA="$(mktemp)"
trap 'rm -f "$TMPDATA"' EXIT
{
  echo "OGRENCI=$OGRENCI"
  echo "SINIF=$SINIF"
  echo "DONEM=$DONEM"
} > "$TMPDATA"

OUT=$(sudo -n "$APPLY" < "$TMPDATA" 2>&1 || true)
if echo "$OUT" | grep -q '^OK '; then
  NEW_HOST="${OUT#OK }"
  # Kullanıcı kopyası
  mkdir -p "$(dirname "$USER_CONF")"
  {
    echo "OGRENCI=\"$OGRENCI\""
    echo "SINIF=\"$SINIF\""
    echo "DONEM=\"$DONEM\""
    echo "HOSTNAME=\"$NEW_HOST\""
  } > "$USER_CONF"

  if (( USE_GUI )); then
    zenity --info \
      --title="MEBKALI — Kayıt Tamamlandı" \
      --width=400 \
      --text="<b>Kimlik kaydedildi.</b>\n\nMakine adı: <tt>$NEW_HOST</tt>\nÖğrenci: $OGRENCI\nSınıf: $SINIF\nDönem: $DONEM\n\nDeğişiklik bir sonraki terminal/oturumdan itibaren görünür." \
      2>/dev/null
  else
    echo "Kayıt OK. Hostname: $NEW_HOST"
  fi
  exit 0
else
  if (( USE_GUI )); then
    zenity --error --text="Kayıt başarısız:\n$OUT" 2>/dev/null
  else
    echo "Kayıt başarısız: $OUT" >&2
  fi
  exit 1
fi
EOF
chmod 0755 "$KIMLIK_USER"
ok "$KIMLIK_USER yazıldı"

# 4) Autostart: ilk girişte otomatik aç
say "4/4 Autostart: $AUTOSTART"
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=MEBKALI Sınıf Kimliği
Name[tr]=MEBKALI Sınıf Kimliği
Comment=İlk açılışta öğrenci kimlik kaydı (zaten kayıtlıysa sessiz çıkar)
Exec=$KIMLIK_USER
OnlyShowIn=XFCE;GNOME;MATE;LXDE;LXQt;KDE;
Terminal=false
NoDisplay=false
X-GNOME-Autostart-Delay=3
EOF
chmod 0644 "$AUTOSTART"
ok "$AUTOSTART yazıldı"

echo
ok "Sınıf kimliği bileşenleri kuruldu."
echo "  Komut    : mebkali-kimlik        (ilk seferde sorar, sonra sessiz)"
echo "  Yeniden  : mebkali-kimlik --force"
echo "  Konum    : $CONF"
warn "İlk grafiksel girişte zenity diyaloğu otomatik açılacak."
