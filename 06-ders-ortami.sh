#!/usr/bin/env bash
# 06-ders-ortami.sh
# Sınıf VM'leri için ekran kilidi + güç yönetimi gevşetmesi.
# 40 dakikalık derslerde öğrenci/öğretmen şifre yazmasın diye:
#   - xfce4-screensaver: idle-lock kapalı, saver kapalı
#   - xfce4-power-manager: DPMS kapalı, blank/sleep yok, hibernate yok
#   - light-locker: varsa devre dışı + autostart silinir
#   - systemd-logind: HandleLidSwitch=ignore (laptop'larda VM kapanmasın)
#
# Çalıştırma: sudo bash 06-ders-ortami.sh
# Geri alma: sudo bash 06-ders-ortami.sh --revert

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-apply}"

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok: $TARGET_USER"; exit 1; }

LOGIND_DROPIN="/etc/systemd/logind.conf.d/50-mebkali-ders.conf"
SIGN="# mebkali-ders-ortami"

# Kullanıcının DBus oturumunda komut çalıştır
run_user() {
  sudo -u "$TARGET_USER" \
       DISPLAY=:0 \
       XAUTHORITY="$TARGET_HOME/.Xauthority" \
       DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
       "$@"
}

xfconf_set() {
  local channel="$1" prop="$2" type="$3" value="$4"
  # xfconf-query: önce -c kanal var mı kontrol et; -n ile property yoksa oluştur
  run_user xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" 2>/dev/null \
    || run_user xfconf-query -c "$channel" -p "$prop" -s "$value" 2>/dev/null || return 1
}

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma: ders-ortamı ayarları temizleniyor..."
  rm -f "$LOGIND_DROPIN" && ok "logind drop-in silindi" || true
  systemctl restart systemd-logind 2>/dev/null || true
  # XFCE: kullanıcı varsayılanlarına dönüş — xfconf property'leri sil
  for p in /lock/enabled /saver/enabled /saver/idle-activation/enabled; do
    run_user xfconf-query -c xfce4-screensaver -p "$p" -r 2>/dev/null || true
  done
  for p in /xfce4-power-manager/dpms-enabled \
           /xfce4-power-manager/blank-on-ac \
           /xfce4-power-manager/dpms-on-ac-off \
           /xfce4-power-manager/dpms-on-ac-sleep \
           /xfce4-power-manager/inactivity-on-ac \
           /xfce4-power-manager/lock-screen-suspend-hibernate \
           /xfce4-power-manager/logind-handle-lid-switch; do
    run_user xfconf-query -c xfce4-power-manager -p "$p" -r 2>/dev/null || true
  done
  # light-locker autostart geri ekle (system-wide bozulmadıysa zaten orada)
  ok "XFCE ekran/güç ayarları varsayılana döndü"
  exit 0
fi

# 1) systemd-logind: lid switch'i yoksay (laptop kapağı kapanınca VM uyumasın)
say "1/4 systemd-logind: HandleLidSwitch=ignore..."
mkdir -p "$(dirname "$LOGIND_DROPIN")"
if [[ ! -f "$LOGIND_DROPIN" ]] || ! grep -q "$SIGN" "$LOGIND_DROPIN" 2>/dev/null; then
  cat > "$LOGIND_DROPIN" <<EOF
$SIGN
# Sınıf VM'inde laptop kapağı kapanınca host uyusa bile guest çalışmaya devam
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
  chmod 0644 "$LOGIND_DROPIN"
  systemctl restart systemd-logind 2>/dev/null || true
  ok "logind drop-in yazıldı: $LOGIND_DROPIN"
else
  ok "logind drop-in zaten ayarlı"
fi

# 2) XFCE oturumu çalışıyor mu? xfconf-query yalnızca user-bus üzerinden çalışır
if ! pgrep -u "$TARGET_USER" -x xfce4-panel >/dev/null 2>&1 \
   && ! pgrep -u "$TARGET_USER" -x xfce4-session >/dev/null 2>&1; then
  warn "XFCE oturumu çalışmıyor — XFCE ayarları yapılamıyor."
  warn "Bu betiği grafiksel oturum açıldıktan sonra tekrar çalıştırın."
  ok "logind ayarı yine de uygulandı"
  exit 0
fi

# 3) xfce4-screensaver: kilit ve saver kapalı
say "2/4 xfce4-screensaver: kilit + saver kapalı..."
SS_OK=1
xfconf_set xfce4-screensaver /lock/enabled bool false       || SS_OK=0
xfconf_set xfce4-screensaver /saver/enabled bool false      || SS_OK=0
xfconf_set xfce4-screensaver /saver/idle-activation/enabled bool false || true
xfconf_set xfce4-screensaver /lock/sleep-activation/enabled bool false || true
xfconf_set xfce4-screensaver /lock/saver-activation/enabled bool false || true
if (( SS_OK )); then
  ok "xfce4-screensaver: lock=false, saver=false"
else
  warn "xfce4-screensaver kanalı yok — Kali'de bu paket kurulu olmayabilir (atlandı)"
fi

# 4) xfce4-power-manager: DPMS off, blank off, sleep off
say "3/4 xfce4-power-manager: DPMS/blank/sleep kapalı..."
xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-enabled bool false || true
xfconf_set xfce4-power-manager /xfce4-power-manager/blank-on-ac uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/blank-on-battery uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-on-ac-off uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-on-ac-sleep uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-on-battery-off uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/dpms-on-battery-sleep uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/inactivity-on-ac uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/inactivity-on-battery uint 0 || true
xfconf_set xfce4-power-manager /xfce4-power-manager/lock-screen-suspend-hibernate bool false || true
xfconf_set xfce4-power-manager /xfce4-power-manager/logind-handle-lid-switch bool false || true
ok "xfce4-power-manager: ders boyunca uyku/kararma yok"

# 5) light-locker (XFCE'de bazı sürümlerde ek kilitleyici): devre dışı bırak
say "4/4 light-locker (varsa) devre dışı..."
if command -v light-locker >/dev/null 2>&1; then
  # Çalışan instance'ı durdur
  pkill -u "$TARGET_USER" -x light-locker 2>/dev/null || true
  # Sistem genelindeki autostart'ı override et (user override)
  USER_AUTO="$TARGET_HOME/.config/autostart"
  install -d -o "$TARGET_USER" -g "$TARGET_USER" "$USER_AUTO"
  cat > "$USER_AUTO/light-locker.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Light Locker
Exec=/bin/true
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=false
$SIGN
EOF
  chown "$TARGET_USER:$TARGET_USER" "$USER_AUTO/light-locker.desktop"
  ok "light-locker autostart override (user)"
else
  ok "light-locker kurulu değil — atlandı"
fi

# 6) Çalışan xfce4-screensaver/power-manager'a sinyal: ayarları yeniden yükle
# (xfconf değişikliği daemon'a anında yansır; ek bir şey gerekmez)

echo
ok "Ders ortamı yapılandırıldı: ekran kararmaz, kilitlenmez, uyumaz."
warn "Geri almak için: sudo bash $0 --revert"
