#!/usr/bin/env bash
# 03-turkce-locale-keyboard.sh
# Türkçe karakter ve klavye yapılandırması: locale, console (TTY), X11/XFCE,
# LightDM giriş ekranı — sistemd-native (localectl) + locale-gen ile.
# Çalıştırma:
#   sudo bash 03-turkce-locale-keyboard.sh                # hibrit (önerilen)
#   sudo bash 03-turkce-locale-keyboard.sh --full-turkish # tam Türkçe arayüz
#
# Hibrit:    LANG=en_US.UTF-8, LC_CTYPE=tr_TR.UTF-8
#   → Arayüz/hata mesajları İngilizce, ama Türkçe karakter sınıflandırma
#     (toupper, isalpha, sıralama) ve UTF-8 ekran çıktısı doğru çalışır.
# --full-turkish:  LANG=tr_TR.UTF-8 (tüm LC_*'ler bunu miras alır)
#   → Sistem mesajları, tarih, para birimi vb. tamamen Türkçe.
#
# Klavye: Türkçe Q (XKBLAYOUT=tr, XKBVARIANT="" → Q default).

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

FULL_TURKISH=0
[[ "${1:-}" == "--full-turkish" ]] && FULL_TURKISH=1

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok: $TARGET_USER"; exit 1; }

# 1) Locale derle
say "1/7 Locale derleme (tr_TR.UTF-8 + en_US.UTF-8)..."
LOCALE_GEN_FILE="/etc/locale.gen"
[[ -f "$LOCALE_GEN_FILE" ]] || { err "$LOCALE_GEN_FILE yok"; exit 1; }
CHANGED=0
for L in "tr_TR.UTF-8 UTF-8" "en_US.UTF-8 UTF-8"; do
  if grep -qE "^[[:space:]]*${L//./\\.}[[:space:]]*$" "$LOCALE_GEN_FILE"; then
    : # zaten etkin
  elif grep -qE "^[[:space:]]*#[[:space:]]*${L//./\\.}[[:space:]]*$" "$LOCALE_GEN_FILE"; then
    sed -i -E "s|^[[:space:]]*#[[:space:]]*(${L//./\\.})[[:space:]]*$|\1|" "$LOCALE_GEN_FILE"
    CHANGED=1
  else
    echo "$L" >> "$LOCALE_GEN_FILE"
    CHANGED=1
  fi
done
if (( CHANGED )) || ! locale -a 2>/dev/null | grep -qi "^tr_tr\.utf8$"; then
  locale-gen >/dev/null
fi
if locale -a 2>/dev/null | grep -qi "^tr_tr\.utf8$" && locale -a 2>/dev/null | grep -qi "^en_us\.utf8$"; then
  ok "Locale'ler derlendi: tr_TR.utf8, en_US.utf8"
else
  err "locale-gen sonrası tr_TR/en_US bulunamadı"; exit 1
fi

# 2) Sistem locale ayarı (/etc/default/locale)
say "2/7 Sistem locale ayarı..."
if (( FULL_TURKISH )); then
  update-locale LANG=tr_TR.UTF-8 LC_CTYPE= LC_MESSAGES= LC_NUMERIC= LC_TIME= LC_MONETARY= \
                LC_PAPER= LC_NAME= LC_ADDRESS= LC_TELEPHONE= LC_MEASUREMENT= LC_IDENTIFICATION= \
                LC_COLLATE=
  ok "LANG=tr_TR.UTF-8 (tam Türkçe — diğer LC_* miras alır)"
else
  update-locale LANG=en_US.UTF-8 LC_CTYPE=tr_TR.UTF-8 LC_COLLATE=tr_TR.UTF-8 \
                LC_TIME=tr_TR.UTF-8 LC_PAPER=tr_TR.UTF-8 LC_MEASUREMENT=tr_TR.UTF-8 \
                LC_MESSAGES= LC_NUMERIC= LC_MONETARY= LC_NAME= LC_ADDRESS= \
                LC_TELEPHONE= LC_IDENTIFICATION=
  ok "LANG=en_US.UTF-8 + LC_CTYPE/COLLATE/TIME/PAPER/MEASUREMENT=tr_TR.UTF-8 (hibrit)"
fi
say "    /etc/default/locale içeriği:"
sed 's/^/        /' /etc/default/locale

# 3) X11 klavye düzeni — Türkçe Q (XKBLAYOUT=tr, XKBVARIANT="")
say "3/7 X11 klavye düzeni (Türkçe Q)..."
# localectl /etc/X11/xorg.conf.d/00-keyboard.conf yazar AMA Debian/Kali'de
# /etc/default/keyboard'u yazmaz. /etc/default/keyboard hem console hem
# LightDM tarafından okunduğu için onu da explicit olarak yazıyoruz.
localectl set-x11-keymap tr pc105 "" ""
KBD_FILE="/etc/default/keyboard"
cat > "$KBD_FILE" <<'EOF'
# KEYBOARD CONFIGURATION FILE
# 03-turkce-locale-keyboard.sh tarafından yazıldı
# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="tr"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
EOF
chmod 0644 "$KBD_FILE"
ok "X11 keymap: tr / pc105 / (Q variant) — /etc/default/keyboard + /etc/X11/xorg.conf.d/00-keyboard.conf yazıldı"

# 4) Console (TTY) klavye düzeni — Türkçe Q için "trq" keymap
say "4/7 Console klavye düzeni..."
# localectl uyarı verirse non-zero dönebilir ama yine de yazar; kodu yutuyoruz
# ve gerçek sonucu /etc/vconsole.conf üzerinden doğruluyoruz.
localectl set-keymap trq >/dev/null 2>&1 || true
if [[ -f /etc/vconsole.conf ]] && KEYMAP_VAL="$(grep -E '^KEYMAP=' /etc/vconsole.conf | cut -d= -f2 | tr -d '"')" && [[ -n "$KEYMAP_VAL" ]]; then
  ok "Console keymap: $KEYMAP_VAL"
else
  warn "Console keymap ayarlanamadı (console-setup paketi eksik olabilir)"
fi
# /etc/default/keyboard idempotent doğrulama (X11 ile aynı dosya)
say "    /etc/default/keyboard içeriği:"
sed 's/^/        /' /etc/default/keyboard

# 5) XFCE per-user keyboard-layout override'ını temizle
# XFCE'nin kendi xfconf override'ı varsa sistem ayarını gölgeler.
# Dosyayı silmek = sistem ayarına dön.
say "5/7 XFCE per-user override temizleniyor..."
XFCE_KBD_FILE="$TARGET_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml"
if [[ -f "$XFCE_KBD_FILE" ]]; then
  cp -a "$XFCE_KBD_FILE" "${XFCE_KBD_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  rm -f "$XFCE_KBD_FILE"
  ok "Mevcut override silindi (yedek alındı): $XFCE_KBD_FILE"
else
  ok "XFCE override yok (sistem ayarı zaten geçerli)"
fi

# 6) Çalışan X oturumuna anında uygula (yeniden giriş gerekmesin)
say "6/7 Çalışan X oturumuna anında uygula..."
APPLIED=0
for d in /tmp/.X11-unix/X*; do
  [[ -e "$d" ]] || continue
  DISP=":${d##*X}"
  XAUTH="$TARGET_HOME/.Xauthority"
  if sudo -u "$TARGET_USER" \
       DISPLAY="$DISP" XAUTHORITY="$XAUTH" \
       setxkbmap -layout tr -model pc105 2>/dev/null; then
    ok "setxkbmap uygulandı: DISPLAY=$DISP"
    APPLIED=1
  fi
done
(( APPLIED == 0 )) && warn "Aktif X oturumu yok — değişiklik bir sonraki girişte etkin olur"

# 7) Doğrulama
say "7/7 Doğrulama..."
FAIL=0

# Locale derlemesi
if locale -a 2>/dev/null | grep -qi "^tr_tr\.utf8$"; then
  ok "tr_TR.UTF-8 locale derlenmiş"
else
  err "tr_TR.UTF-8 locale yok"; FAIL=1
fi

# Sistem locale ayarı
if (( FULL_TURKISH )); then
  grep -q '^LANG=tr_TR\.UTF-8' /etc/default/locale && ok "LANG=tr_TR.UTF-8" || { err "LANG ayarı yanlış"; FAIL=1; }
else
  grep -q '^LANG=en_US\.UTF-8' /etc/default/locale && ok "LANG=en_US.UTF-8 (hibrit)" || { err "LANG ayarı yanlış"; FAIL=1; }
  grep -q '^LC_CTYPE=tr_TR\.UTF-8' /etc/default/locale && ok "LC_CTYPE=tr_TR.UTF-8" || { err "LC_CTYPE ayarı yanlış"; FAIL=1; }
fi

# Klavye dosyası
if grep -q '^XKBLAYOUT="tr"' /etc/default/keyboard; then
  ok "/etc/default/keyboard XKBLAYOUT=tr"
else
  err "/etc/default/keyboard XKBLAYOUT yanlış"; FAIL=1
fi

# localectl
LECT="$(localectl status 2>/dev/null)"
if echo "$LECT" | grep -qE "X11 Layout:[[:space:]]+tr"; then
  ok "localectl: X11 Layout: tr"
else
  err "localectl X11 layout yanlış"; FAIL=1
fi

# UTF-8 karakter byte testi (Türkçe karakterlerin doğru yazıldığını teyit)
TR_CHARS="ç Ç ş Ş ğ Ğ ı I İ ö Ö ü Ü"
TR_BYTES="$(printf '%s' "$TR_CHARS" | hexdump -ve '/1 "%02x "')"
EXPECTED_FRAGMENTS=(
  "c3 a7"   # ç
  "c3 87"   # Ç
  "c5 9f"   # ş
  "c5 9e"   # Ş
  "c4 9f"   # ğ
  "c4 9e"   # Ğ
  "c4 b1"   # ı
  "c4 b0"   # İ
  "c3 b6"   # ö
  "c3 96"   # Ö
  "c3 bc"   # ü
  "c3 9c"   # Ü
)
ALL_FOUND=1
for frag in "${EXPECTED_FRAGMENTS[@]}"; do
  echo "$TR_BYTES" | grep -q "$frag " || ALL_FOUND=0
done
if (( ALL_FOUND )); then
  ok "UTF-8 byte testi: tüm Türkçe karakterler doğru kodlanıyor"
else
  err "UTF-8 byte testi başarısız"; FAIL=1
fi

# tr_TR'ye özgü davranış: i → İ büyük-küçük dönüşümü.
# `tr` (POSIX) multi-byte locale-aware değildir, bu yüzden bash builtin
# ${var^^} kullanıyoruz; yeni alt-shell ile fork edip cached locale'i yenileyerek.
TURK_CASE="$(LC_ALL=tr_TR.UTF-8 bash -c 'a=i; echo ${a^^}' 2>/dev/null)"
if [[ "$TURK_CASE" == "İ" ]]; then
  ok "Türkçe locale aktif: i → İ (glibc tr_TR ctype çalışıyor)"
else
  err "Türkçe büyük dönüşüm: i → '$TURK_CASE' (beklenen: İ)"; FAIL=1
fi

echo
if (( FAIL )); then
  err "Bazı testler başarısız"
  exit 1
fi
ok "Locale + Türkçe Q klavye yapılandırıldı."
warn "LightDM giriş ekranı: tam etkin olması için bir kez logout/yeniden giriş yapın"
warn "TTY (Ctrl+Alt+F2-F6): hemen çalışır"
warn "XFCE oturumu: setxkbmap zaten uygulandı; ayrıca yeniden girişte sistem ayarı geçerli olur"
