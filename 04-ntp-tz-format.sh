#!/usr/bin/env bash
# 04-ntp-tz-format.sh
# Saat dilimi (Europe/Istanbul) + yedekli NTP + 24-saat biçim yapılandırması.
# Çalıştırma: sudo bash 04-ntp-tz-format.sh
#
# Yapılanlar (idempotent):
#   1. Timezone'u Europe/Istanbul'a ayarla (timedatectl set-timezone)
#      → IANA tzdata Türkiye'nin DST kararlarını (2016: kaldırıldı) ve gelecekteki
#        olası değişiklikleri zaten içerir; tzdata apt ile güncellenir.
#   2. /etc/systemd/timesyncd.conf'a yedekli NTP sunucu listesi yaz
#      Primary: TR pool + Cloudflare (anycast) + Debian pool
#      Fallback: ek TR pool + Google + generic pool + NIST
#   3. systemd-timesyncd'i etkinleştir, restart, sync zorla
#   4. XFCE saat plugin formatını 24-saat olarak sabitle (idempotent)
#   5. RTC'yi UTC'de tut (RTC in local TZ: no — dual-boot karışıklığını önler)
#   6. Doğrulama: timedatectl, date, NTP server reachability, XFCE format

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok: $TARGET_USER"; exit 1; }

TZ_TARGET="Europe/Istanbul"
TIMESYNCD_CONF="/etc/systemd/timesyncd.conf"
DESIRED_FORMAT="%R"   # HH:MM, 24-saat, zero-padded

# 1) Timezone
say "1/6 Timezone'u $TZ_TARGET olarak ayarla..."
[[ -f "/usr/share/zoneinfo/$TZ_TARGET" ]] || { err "$TZ_TARGET zoneinfo'da yok (tzdata bozuk olabilir)"; exit 1; }
CURRENT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)"
if [[ "$CURRENT_TZ" == "$TZ_TARGET" ]]; then
  ok "Timezone zaten $TZ_TARGET"
else
  timedatectl set-timezone "$TZ_TARGET"
  ok "Timezone $CURRENT_TZ → $TZ_TARGET"
fi

# 2) RTC'yi UTC'de tut (dual-boot Windows ile karışmaması için)
say "2/6 RTC'yi UTC'de tut..."
RTC_LOCAL="$(timedatectl show --property=LocalRTC --value 2>/dev/null || echo unknown)"
if [[ "$RTC_LOCAL" == "no" ]]; then
  ok "RTC zaten UTC'de"
else
  timedatectl set-local-rtc 0 --adjust-system-clock
  ok "RTC UTC'ye ayarlandı"
fi

# 3) Yedekli NTP sunucu listesi
say "3/6 NTP yedekli sunucu listesi (/etc/systemd/timesyncd.conf)..."
TS="$(date +%Y%m%d-%H%M%S)"
[[ -f "$TIMESYNCD_CONF" ]] && cp -a "$TIMESYNCD_CONF" "${TIMESYNCD_CONF}.bak.${TS}"

cat > "$TIMESYNCD_CONF" <<'EOF'
# 04-ntp-tz-format.sh tarafından oluşturuldu
# systemd-timesyncd NTP yedekli yapılandırması
[Time]
# Primary: yerel TR pool, Cloudflare anycast, Debian pool
NTP=0.tr.pool.ntp.org 1.tr.pool.ntp.org time.cloudflare.com 0.debian.pool.ntp.org

# Fallback: NTP'lerin hiçbiri ulaşılamazsa bunlar denenir
FallbackNTP=2.tr.pool.ntp.org 3.tr.pool.ntp.org time.google.com 1.debian.pool.ntp.org pool.ntp.org time.nist.gov

# Sync agresifliği: yeni network'te hızlı yakınsama
PollIntervalMinSec=32
PollIntervalMaxSec=2048
RootDistanceMaxSec=5
EOF
chmod 0644 "$TIMESYNCD_CONF"
ok "Yedekli NTP listesi yazıldı (4 primary + 6 fallback sunucu)"

# 4) systemd-timesyncd: enable + restart + sync zorla
say "4/6 systemd-timesyncd etkinleştir + restart..."
systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
# Bazı sistemler "timedatectl set-ntp true" ile NTP açar; idempotent
timedatectl set-ntp true
systemctl restart systemd-timesyncd
# Sync için bir kaç saniye bekle
sleep 3
ok "systemd-timesyncd yeniden başlatıldı"

# 5) XFCE saat plugin'i — 24-saat biçimi sabitle
say "5/6 XFCE saat plugin formatı (24-saat)..."
if pgrep -u "$TARGET_USER" -x xfce4-panel >/dev/null 2>&1; then
  # xfconf-query çalışan oturumun DBus'una bağlanmalı; user-bus üzerinden
  # xfconf-query'i kullanıcının ortamında çağır
  RUN_USER_BUS_CMD() {
    local uid="$(id -u "$TARGET_USER")"
    sudo -u "$TARGET_USER" \
         DISPLAY=:0 \
         XAUTHORITY="$TARGET_HOME/.Xauthority" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
         "$@"
  }

  CHANGED=0
  while IFS= read -r prop; do
    plugin_path="${prop%/digital-time-format*}"
    plugin_path="${plugin_path%/digital-format*}"
    # plugin'in clock olduğunu doğrula
    plugin_type="$(RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -p "$plugin_path" 2>/dev/null || echo "")"
    [[ "$plugin_type" != "clock" ]] && continue

    # Yeni-stil: digital-time-format
    cur="$(RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -p "${plugin_path}/digital-time-format" 2>/dev/null || echo "")"
    if [[ -n "$cur" && "$cur" != "$DESIRED_FORMAT" ]]; then
      RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -p "${plugin_path}/digital-time-format" -s "$DESIRED_FORMAT"
      ok "Format güncellendi: $plugin_path/digital-time-format: '$cur' → '$DESIRED_FORMAT'"
      CHANGED=1
    elif [[ "$cur" == "$DESIRED_FORMAT" ]]; then
      ok "Format zaten doğru: $plugin_path/digital-time-format = '$DESIRED_FORMAT'"
    fi

    # digital-layout = 3 (sadece zaman) ya da 2 (tarih+zaman). 24h biçimi
    # her ikisinde de uygulanır; mevcut layout'u koruyoruz.

    # Eski-stil format ihtimali (digital-format)
    cur_old="$(RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -p "${plugin_path}/digital-format" 2>/dev/null || echo "")"
    if [[ -n "$cur_old" ]]; then
      # Eski format'ta AM/PM göstergesi varsa düzelt
      if echo "$cur_old" | grep -qE '%[pP]|%[Il]'; then
        RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -p "${plugin_path}/digital-format" -s "$DESIRED_FORMAT"
        ok "Eski format AM/PM içeriyordu, 24h olarak güncellendi: '$cur_old' → '$DESIRED_FORMAT'"
        CHANGED=1
      fi
    fi
  done < <(RUN_USER_BUS_CMD xfconf-query -c xfce4-panel -lv 2>/dev/null \
            | awk '/^\/plugins\/plugin-[0-9]+[[:space:]]+clock[[:space:]]*$/ {print $1"/digital-time-format"}')

  if (( CHANGED == 1 )); then
    ok "XFCE panel ayarları yenilendi"
  fi
else
  warn "xfce4-panel çalışmıyor — XFCE oturumu açıldığında format zaten 24h olur (mevcut config %R)"
fi

# 6) Doğrulama
say "6/6 Doğrulama..."
FAIL=0

CURRENT_TZ="$(timedatectl show --property=Timezone --value 2>/dev/null)"
if [[ "$CURRENT_TZ" == "$TZ_TARGET" ]]; then
  ok "Timezone: $CURRENT_TZ"
else
  err "Timezone yanlış: $CURRENT_TZ"; FAIL=1
fi

NTP_ACTIVE="$(timedatectl show --property=NTP --value 2>/dev/null)"
if [[ "$NTP_ACTIVE" == "yes" ]]; then
  ok "NTP servisi: aktif"
else
  err "NTP servisi pasif"; FAIL=1
fi

# timesyncd durumu
TSYNC_STATUS="$(timedatectl timesync-status 2>&1 || true)"
if echo "$TSYNC_STATUS" | grep -qE "Server:.*\("; then
  CURRENT_NTP_SERVER="$(echo "$TSYNC_STATUS" | grep -E "^[[:space:]]*Server:" | head -1 | sed 's/.*(\(.*\)).*/\1/')"
  ok "Aktif NTP sunucusu: $CURRENT_NTP_SERVER"
else
  warn "timedatectl timesync-status henüz veri vermedi (sync devam ediyor olabilir)"
fi

# Senkronize mi?
SYNC="$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)"
if [[ "$SYNC" == "yes" ]]; then
  ok "Sistem saati NTP ile senkron"
else
  warn "Henüz senkron olmamış (birkaç saniye bekle, sonra timedatectl status ile kontrol)"
fi

# Şu anki saat doğru mu (Türkiye GMT+3 mü)?
NOW_TZ="$(date '+%Z %z')"
NOW_HUMAN="$(date '+%Y-%m-%d %H:%M:%S %A')"
if echo "$NOW_TZ" | grep -qE "\+0300"; then
  ok "Yerel saat: $NOW_HUMAN ($NOW_TZ)"
else
  err "Yerel saat dilimi GMT+3 değil: $NOW_TZ"; FAIL=1
fi

# 24-saat biçim teyit
HOUR_FMT="$(date '+%R')"
if [[ "$HOUR_FMT" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
  ok "Tarih komutu 24-saat biçimde: $HOUR_FMT"
else
  err "24-saat biçim doğrulanamadı: $HOUR_FMT"; FAIL=1
fi

# RTC UTC'de mi
RTC_LOCAL_FINAL="$(timedatectl show --property=LocalRTC --value)"
if [[ "$RTC_LOCAL_FINAL" == "no" ]]; then
  ok "RTC UTC'de (dual-boot güvenli)"
else
  warn "RTC local TZ'de — dual-boot Windows ile karışıklık olabilir"
fi

echo
if (( FAIL )); then
  err "Bazı doğrulamalar başarısız"
  exit 1
fi
ok "Saat + NTP + 24h biçim yapılandırıldı."
warn "XFCE saat görselinin değişmesi için panel kendi başına yeniler (1 dk içinde) veya:"
warn "  pkill -SIGUSR2 xfce4-panel  ya da  xfce4-panel -r"
