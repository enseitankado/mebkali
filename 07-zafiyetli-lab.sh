#!/usr/bin/env bash
# 07-zafiyetli-lab.sh
# Sınıf içi zafiyetli laboratuvar: Docker tabanlı DVWA (Damn Vulnerable Web App).
# Bir kez imaj çekildikten sonra ders boyunca tamamen internetsiz çalışır.
#
# Çalıştırma:
#   sudo bash 07-zafiyetli-lab.sh           # kur (idempotent)
#   sudo bash 07-zafiyetli-lab.sh --remove  # konteyneri+launcher'ı kaldır (imajı tut)
#
# Sonrası (kullanıcı):
#   mebkali-lab basla     # DVWA'yı başlat
#   mebkali-lab durdur    # durdur
#   mebkali-lab durum     # çalışıyor mu?
#   mebkali-lab sifirla   # veritabanını sıfırla (DVWA setup.php benzeri)
#   firefox http://127.0.0.1:8080/

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-install}"

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok"; exit 1; }

IMAGE="vulnerables/web-dvwa"
CONTAINER="mebkali-dvwa"
HOST_PORT=8080
LAUNCHER="/usr/local/bin/mebkali-lab"
DESKTOP_FILE="/usr/share/applications/mebkali-lab.desktop"
USER_DESKTOP_LINK="$TARGET_HOME/Desktop/MEBKALI Lab (DVWA).desktop"

if [[ "$MODE" == "--remove" ]]; then
  say "Kaldırma: container + launcher (imaj korunur)..."
  docker rm -f "$CONTAINER" 2>/dev/null || true
  rm -f "$LAUNCHER" "$DESKTOP_FILE" "$USER_DESKTOP_LINK"
  ok "Konteyner ve launcher silindi. İmaj korunuyor ($IMAGE)."
  exit 0
fi

# 1) Docker kurulu mu?
say "1/5 Docker yükleme/doğrulama..."
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io >/dev/null
  ok "docker.io paketi kuruldu"
else
  ok "docker zaten kurulu ($(docker --version 2>/dev/null | head -1))"
fi

# Docker servisi açık olsun
if ! systemctl is-enabled docker >/dev/null 2>&1; then
  systemctl enable docker >/dev/null 2>&1 || true
fi
if ! systemctl is-active docker >/dev/null 2>&1; then
  systemctl start docker
fi
ok "docker servisi aktif"

# 2) Kullanıcıyı docker grubuna ekle (sudo'suz docker)
say "2/5 Kullanıcıyı docker grubuna ekle..."
if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  ok "$TARGET_USER zaten docker grubunda"
else
  usermod -aG docker "$TARGET_USER"
  ok "$TARGET_USER docker grubuna eklendi (oturumu kapat→aç ile etkin olur)"
fi

# 3) DVWA imajını çek (çekilince offline çalışır)
say "3/5 DVWA imajı (${IMAGE}) — internet üzerinden çekiliyor..."
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  ok "İmaj zaten yerel diskte"
else
  if docker pull "$IMAGE"; then
    ok "İmaj yerel diske indirildi (~700 MB)"
  else
    err "İmaj çekilemedi — internet erişimi/MEB sertifika ayarı kontrol edin."
    err "Önce 01-mitm-cert-trust.sh ve 02-apt-mirror-fix.sh adımlarının başarılı olması gerekir."
    exit 1
  fi
fi

# 4) Konteyneri oluştur (yoksa); ilk seferde yarat, ardından start/stop ile kullan
say "4/5 Konteyner ($CONTAINER) hazırlanıyor..."
if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
  ok "Konteyner zaten mevcut"
else
  docker create \
    --name "$CONTAINER" \
    --restart=no \
    -p "127.0.0.1:${HOST_PORT}:80" \
    "$IMAGE" >/dev/null
  ok "Konteyner oluşturuldu (port 127.0.0.1:${HOST_PORT} → 80)"
fi

# 5) mebkali-lab launcher
say "5/5 mebkali-lab komutu + masaüstü kısayolu..."
cat > "$LAUNCHER" <<'WRAP'
#!/usr/bin/env bash
# mebkali-lab — DVWA konteynerini başlat/durdur/sıfırla
# mebkali tarafından üretildi (07-zafiyetli-lab.sh)
set -uo pipefail

C="mebkali-dvwa"
PORT=8080
URL="http://127.0.0.1:${PORT}/"

usage() {
  cat <<EOF
Kullanım: mebkali-lab <komut>

Komutlar:
  basla      DVWA konteynerini başlat
  durdur     DVWA konteynerini durdur
  durum      Çalışıyor mu, port hangisi
  url        Tarayıcı için adresi yazdır ($URL)
  ac         Tarayıcıda DVWA'yı aç
  sifirla    Konteyneri sil ve yeniden yarat (DB sıfırlanır)
  giris      DVWA giriş bilgilerini hatırlat

DVWA varsayılan kullanıcı: admin / password
İlk açılışta /setup.php'ye gidip "Create / Reset Database" tıkla.
EOF
}

case "${1:-}" in
  basla|start)
    if ! docker container inspect "$C" >/dev/null 2>&1; then
      echo "Konteyner yok. Önce: sudo bash 07-zafiyetli-lab.sh"
      exit 1
    fi
    docker start "$C" >/dev/null && echo "DVWA çalışıyor: $URL"
    ;;
  durdur|stop)
    docker stop "$C" >/dev/null 2>&1 && echo "DVWA durduruldu." || echo "Zaten kapalı."
    ;;
  durum|status)
    if docker ps --format '{{.Names}}' | grep -qx "$C"; then
      echo "Çalışıyor: $URL"
      docker port "$C"
    else
      echo "Kapalı (basla ile başlat)"
    fi
    ;;
  url)
    echo "$URL"
    ;;
  ac|open)
    docker start "$C" >/dev/null 2>&1 || true
    xdg-open "$URL" >/dev/null 2>&1 &
    ;;
  sifirla|reset)
    docker rm -f "$C" >/dev/null 2>&1 || true
    docker create --name "$C" --restart=no -p "127.0.0.1:${PORT}:80" vulnerables/web-dvwa >/dev/null
    docker start "$C" >/dev/null
    echo "Konteyner yeniden oluşturuldu ve başlatıldı: $URL"
    echo "Tarayıcıda /setup.php → Create / Reset Database tıkla."
    ;;
  giris|login)
    cat <<EOF
DVWA giriş bilgileri:
  Kullanıcı: admin
  Şifre   : password
İlk açılışta: ${URL}setup.php → "Create / Reset Database"
EOF
    ;;
  ""|-h|--help|yardim)
    usage
    ;;
  *)
    echo "Bilinmeyen komut: $1"
    usage
    exit 2
    ;;
esac
WRAP
chmod 0755 "$LAUNCHER"
ok "$LAUNCHER yazıldı"

# Sistem geneli .desktop launcher (Applications menüsünde "MEBKALI Lab")
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=MEBKALI Lab (DVWA)
Name[tr]=MEBKALI Lab (DVWA)
Comment=Damn Vulnerable Web App — yerel zafiyetli laboratuvar
Comment[tr]=Yerel zafiyetli web uygulaması (DVWA) — sınıf laboratuvarı
Exec=mebkali-lab ac
Icon=applications-development
Terminal=false
Categories=Development;Security;Education;
Keywords=dvwa;lab;web;sql;xss;mebkali;
EOF
chmod 0644 "$DESKTOP_FILE"
ok "$DESKTOP_FILE yazıldı"

# Kullanıcı masaüstüne kopya (var ise overwrite)
if [[ -d "$TARGET_HOME/Desktop" ]]; then
  cp "$DESKTOP_FILE" "$USER_DESKTOP_LINK"
  chmod 0755 "$USER_DESKTOP_LINK"
  chown "$TARGET_USER:$TARGET_USER" "$USER_DESKTOP_LINK"
  ok "Masaüstüne kısayol kopyalandı"
fi

echo
ok "Zafiyetli laboratuvar hazır. Kullanım:"
echo "  mebkali-lab basla     # başlat"
echo "  mebkali-lab ac        # tarayıcıda aç"
echo "  mebkali-lab durum     # durumu gör"
echo "  http://127.0.0.1:${HOST_PORT}/setup.php  # ilk açılışta DB kur"
warn "Yeni docker grubu için kullanıcı bir kez oturum açıp kapatmalı."
