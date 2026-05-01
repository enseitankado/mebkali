#!/usr/bin/env bash
# 05-vbox-host-paylasim.sh
# VirtualBox guest tarafında iki yönlü pano + shared folder + drag-drop için
# gerekli her şeyi idempotent garantiler. Host-side ayarları net yazdırır.
#
# Çalıştırma:
#   sudo bash 05-vbox-host-paylasim.sh                  # konfigürasyon (default)
#   sudo bash 05-vbox-host-paylasim.sh --test-clipboard # iki yönlü pano testi
#   sudo bash 05-vbox-host-paylasim.sh --test-shared    # shared folder testi
#   sudo bash 05-vbox-host-paylasim.sh --print-host-cmds # host'ta çalıştırılacak VBoxManage komutları
#
# Mimari:
#   Guest <─ hipervizör IPC ─> Host
#   - Pano: VBoxClient --clipboard daemon (otomatik başlar)
#   - Drag-drop: VBoxClient --draganddrop daemon
#   - Dosya: vboxsf kernel modülü ile /media/sf_<isim> mount
#   Tüm trafik hipervizör üzerinden — ağ kullanılmaz, kapsamı izole.
#
# Güvenlik:
#   - vboxsf mount sadece "vboxsf" grup üyesi kullanıcılara açılır
#   - Host'ta kullanıcının seçtiği SPESİFİK klasör paylaşılır (tüm host fs DEĞİL)
#   - Kanal hipervizöre bağlı; ağ üzerinden erişim yok

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }
hl()   { printf "%s%s%s\n"     "$CYAN"   "$*" "$NC"; }

MODE="${1:-config}"

case "$MODE" in
  --test-clipboard)
    # X session'da çalıştırılmalı, root gerekmez
    DISP="${DISPLAY:-:0}"
    XAUTH="${XAUTHORITY:-${HOME}/.Xauthority}"
    if [[ -z "$XAUTH" ]] || [[ ! -e "$XAUTH" ]]; then
      XAUTH="/home/${SUDO_USER:-kali}/.Xauthority"
    fi
    say "İki yönlü pano testi (DISPLAY=$DISP)"
    # Test 1: Guest → Host
    MARKER="MEB-TEST-$(date +%s)-$$"
    if [[ $EUID -eq 0 ]]; then
      sudo -u "${SUDO_USER:-kali}" DISPLAY="$DISP" XAUTHORITY="$XAUTH" \
        bash -c "printf '%s' '$MARKER' | xclip -selection clipboard"
    else
      printf '%s' "$MARKER" | xclip -selection clipboard
    fi
    hl "  Guest panosuna kopyalandı: $MARKER"
    hl "  ⮕ HOST'A geç, herhangi bir uygulamada Ctrl+V yap."
    hl "     Yapıştırılan değer '$MARKER' ile aynı mı?"
    read -r -p "  [E/h] " R
    if [[ "${R,,}" == "h" ]]; then
      err "Guest → Host pano çalışmıyor"
      warn "Host VM ayarı: General → Advanced → Shared Clipboard = Bidirectional"
      exit 1
    else
      ok "Guest → Host pano OK"
    fi
    # Test 2: Host → Guest
    HOST_MARKER="MEB-HOST-$(date +%s)"
    hl "  Şimdi HOST'TA herhangi bir uygulamada bu metni kopyala:"
    hl "     $HOST_MARKER"
    hl "  Kopyaladıktan sonra Enter'a bas..."
    read -r
    if [[ $EUID -eq 0 ]]; then
      GOT="$(sudo -u "${SUDO_USER:-kali}" DISPLAY="$DISP" XAUTHORITY="$XAUTH" xclip -selection clipboard -o 2>/dev/null)"
    else
      GOT="$(xclip -selection clipboard -o 2>/dev/null)"
    fi
    if [[ "$GOT" == "$HOST_MARKER" ]]; then
      ok "Host → Guest pano OK ('$GOT')"
    else
      err "Host → Guest pano başarısız (panoda: '$GOT')"
      warn "Host VM ayarı bidirectional mı kontrol et"
      exit 1
    fi
    ok "İki yönlü pano testi başarılı"
    exit 0
    ;;
  --test-shared)
    # /media/sf_<*> mount edilmiş bir klasör var mı, içine yazma testi
    say "Shared folder testi"
    MOUNTS=()
    while IFS= read -r line; do
      MOUNTS+=("$line")
    done < <(mount -t vboxsf 2>/dev/null | awk '{print $3}')
    if (( ${#MOUNTS[@]} == 0 )); then
      err "Hiç vboxsf mount bulunamadı"
      warn "Host'ta Shared Folder eklenmiş mi? --print-host-cmds ile talimat al"
      exit 1
    fi
    for m in "${MOUNTS[@]}"; do
      ok "Mount: $m"
      TEST_FILE="$m/.mebkali-test-$$"
      if [[ $EUID -eq 0 ]]; then
        sudo -u "${SUDO_USER:-kali}" bash -c "echo 'guest-yazdi' > '$TEST_FILE'" 2>/dev/null && ok "  Guest yazma OK" || warn "  Guest yazamadı (yetki?)"
        sudo -u "${SUDO_USER:-kali}" rm -f "$TEST_FILE" 2>/dev/null
      else
        echo 'guest-yazdi' > "$TEST_FILE" 2>/dev/null && ok "  Guest yazma OK" || warn "  Guest yazamadı (yetki?)"
        rm -f "$TEST_FILE" 2>/dev/null
      fi
      ls -la "$m" 2>&1 | head -5 | sed 's/^/    /'
    done
    exit 0
    ;;
  --print-host-cmds)
    cat <<HOSTHELP
${CYAN}─── HOST üzerinde çalıştırılacak komutlar ───${NC}

VirtualBox 7.x VM adınız: ${CYAN}<VM_ADI>${NC} (genellikle "Kali" veya "Kali-Linux-2026.1")

# 1) Pano + Drag-and-Drop bidirectional
VBoxManage modifyvm "<VM_ADI>" --clipboard-mode bidirectional
VBoxManage modifyvm "<VM_ADI>" --draganddrop bidirectional

# 2) Shared Folder ekleme (örnek: ~/Paylasim klasörünü "paylasim" adıyla paylaş)
VBoxManage sharedfolder add "<VM_ADI>" \\
    --name "paylasim" \\
    --hostpath "\$HOME/Paylasim" \\
    --automount \\
    --auto-mount-point "/media/sf_paylasim"
mkdir -p "\$HOME/Paylasim"

# 3) Mevcut shared folder'ları gör
VBoxManage showvminfo "<VM_ADI>" | grep -A1 "Shared folders"

# 4) Bir paylaşımı silmek için
VBoxManage sharedfolder remove "<VM_ADI>" --name "paylasim"

${YELLOW}NOT:${NC} VM kapalıyken bu komutlar VM ayarına yazılır (kalıcı).
       VM açıkken çalıştırılırsa "transient" olur (next boot kaybolur).
       Kalıcı için ${CYAN}VM'yi kapat → komutu çalıştır → VM'yi başlat${NC}.

${CYAN}─── Alternatif: GUI yolu ───${NC}
  VirtualBox Manager → VM seç → Settings:
    1. General → Advanced
       • Shared Clipboard: Bidirectional
       • Drag'n'Drop: Bidirectional
    2. Shared Folders → Add (klasör ikonu)
       • Folder Path: host'taki paylaşılacak dizin
       • Folder Name: "paylasim" (Kali'de /media/sf_paylasim olur)
       • ✓ Auto-mount  ✓ Make Permanent
HOSTHELP
    exit 0
    ;;
  config|"")
    : # ana akışa düş
    ;;
  *)
    err "Bilinmeyen mod: $MODE"
    err "Kullanım: $0 [config|--test-clipboard|--test-shared|--print-host-cmds]"
    exit 1
    ;;
esac

# === Konfigürasyon modu (default) ===
[[ $EUID -eq 0 ]] || { err "Bu mod root yetkisi gerektirir. sudo bash $0"; exit 1; }

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok: $TARGET_USER"; exit 1; }

# 1) Sanallaştırma tespiti
say "1/7 Sanallaştırma tespiti..."
VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
DMI_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
if [[ "$VIRT" == "oracle" || "$DMI_PRODUCT" == "VirtualBox" ]]; then
  ok "VirtualBox guest tespit edildi ($VIRT, $DMI_PRODUCT)"
else
  err "Bu makine VirtualBox guest değil ($VIRT, $DMI_PRODUCT). Betik VirtualBox'a özgüdür."
  exit 1
fi

# 2) Guest Additions paketleri
say "2/7 Guest Additions paketleri..."
NEED_INSTALL=()
for pkg in virtualbox-guest-utils virtualbox-guest-x11; do
  if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
    ok "$pkg kurulu"
  else
    NEED_INSTALL+=("$pkg")
  fi
done
if (( ${#NEED_INSTALL[@]} > 0 )); then
  say "Eksik paketler kuruluyor: ${NEED_INSTALL[*]}"
  if apt-get install -y --no-install-recommends "${NEED_INSTALL[@]}"; then
    ok "Paketler kuruldu"
  else
    err "Paket kurulumu başarısız (apt çalışıyor mu? 02-apt-mirror-fix.sh çalıştırılmış mı?)"
    exit 1
  fi
fi

# 3) Pano araçları (xclip — terminalden pano kullanımı için)
say "3/7 Pano komut satırı araçları (xclip + xsel)..."
PANO_NEED=()
command -v xclip >/dev/null 2>&1 || PANO_NEED+=("xclip")
command -v xsel  >/dev/null 2>&1 || PANO_NEED+=("xsel")
if (( ${#PANO_NEED[@]} > 0 )); then
  apt-get install -y --no-install-recommends "${PANO_NEED[@]}" >/dev/null 2>&1 \
    && ok "Kuruldu: ${PANO_NEED[*]}" \
    || warn "Bazı pano araçları kurulamadı: ${PANO_NEED[*]}"
fi
command -v xclip >/dev/null 2>&1 && ok "xclip mevcut"

# 4) Kernel modülleri yüklü mü
say "4/7 Kernel modülleri (vboxguest, vboxsf)..."
for m in vboxguest vboxsf; do
  if lsmod | awk '{print $1}' | grep -qx "$m"; then
    ok "$m yüklü"
  else
    if modprobe "$m" 2>/dev/null; then
      ok "$m yüklendi"
    else
      err "$m yüklenemedi (paket eksik veya kernel uyumsuz)"
      exit 1
    fi
  fi
done

# 5) vboxsf grup üyeliği (shared folder erişimi için zorunlu)
say "5/7 vboxsf grup üyeliği..."
if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx vboxsf; then
  ok "$TARGET_USER zaten vboxsf üyesi"
else
  usermod -aG vboxsf "$TARGET_USER"
  ok "$TARGET_USER vboxsf grubuna eklendi (yeniden login gerek)"
fi

# 6) VBoxClient daemon'lar (pano + drag-drop + seamless display)
say "6/7 VBoxClient daemon'lar..."
PROC_LIST="$(pgrep -af '/usr/bin/VBoxClient' 2>/dev/null || true)"
for sub in clipboard draganddrop seamless vmsvga-session; do
  if echo "$PROC_LIST" | grep -q -- "--$sub"; then
    ok "VBoxClient --$sub çalışıyor"
  else
    warn "VBoxClient --$sub çalışmıyor — XFCE oturumu içinde başlatılmalı"
    # X session içinde başlatma denemesi
    if pgrep -u "$TARGET_USER" -x xfce4-panel >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" \
        /usr/bin/VBoxClient "--$sub" 2>/dev/null && ok "  Başlatıldı: --$sub" || true
    fi
  fi
done

# 7) Shared folder mount kontrolü ve ergonomi
say "7/7 Shared folder durumu..."
SF_MOUNTS=()
while IFS= read -r line; do
  SF_MOUNTS+=("$line")
done < <(mount -t vboxsf 2>/dev/null | awk '{print $3}')
if (( ${#SF_MOUNTS[@]} > 0 )); then
  for m in "${SF_MOUNTS[@]}"; do
    ok "Mount: $m"
  done
  # Kullanıcı home'unda kolay erişim için sembolik link
  for m in "${SF_MOUNTS[@]}"; do
    base="$(basename "$m")"
    LINK="$TARGET_HOME/$base"
    if [[ -L "$LINK" ]]; then
      :
    elif [[ ! -e "$LINK" ]]; then
      sudo -u "$TARGET_USER" ln -s "$m" "$LINK" 2>/dev/null \
        && ok "Sembolik link: ~/$base → $m" || true
    fi
  done
else
  warn "Hiç shared folder mount edilmemiş. Host-side ayar gerekli:"
  warn "  $0 --print-host-cmds  ← host'ta çalıştırılacak komutlar"
fi

# Özet ve sonraki adımlar
echo
hl "━━━ Yapılandırma tamamlandı ━━━"
echo
hl "Sıradaki teyit adımları:"
printf "  %sBu betikleri çalıştır:%s\n" "$YELLOW" "$NC"
echo "    bash $0 --print-host-cmds       # host'ta yapılacaklar"
echo "    bash $0 --test-clipboard        # iki yönlü pano testi (X oturumunda)"
echo "    bash $0 --test-shared           # shared folder testi"
echo
warn "Eğer vboxsf grubuna YENİ eklendiysen: bir kez logout/login (grup üyeliği aktif olur)"
warn "Host VM ayarı eksikse pano/drag-drop tek yönlü kalır — --print-host-cmds çıktısını uygula"
