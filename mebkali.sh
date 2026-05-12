#!/usr/bin/env bash
# mebkali.sh
# MEB ağı arkasındaki Kali makinelerini adım adım kullanılır hale getiren
# yönetici betik. 5 alt betiği sırayla çağırır; her adımda önce engeli ve
# çözümü anlatır, sonra kullanıcıdan onay alır.
#
# Çalıştırma:
#   bash mebkali.sh           # her adımda onay (E/h/q)
#   bash mebkali.sh -y        # tüm adımlar onaysız (otomatik evet)
#   SUDO_PASS=kali bash ...   # sudo şifresini ortam değişkeniyle geçir

set -uo pipefail

# Çerçeve genişlik hesabı için UTF-8 yerel ayarı zorunlu
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_NAME="$(basename "$(pwd)")"

# ─── Argümanlar ────────────────────────────────────────────────────────
AUTO_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=1 ;;
    -h|--help)
      cat <<EOF
Kullanım: bash mebkali.sh [-y|--yes] [-h|--help]

  -y, --yes    Tüm adımları onaysız (otomatik evet) çalıştır.
  -h, --help   Bu yardımı göster.

Ortam değişkenleri:
  SUDO_PASS    Sudo şifresi (varsayılan: "kali"). Sudo sorgusunu atlamak için.
EOF
      exit 0
      ;;
  esac
done

# ─── Renkler & glifler ─────────────────────────────────────────────────
RST=$'\e[0m';    BOLD=$'\e[1m';   DIM=$'\e[2m'
CYAN=$'\e[36m';  GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'
MAGENTA=$'\e[35m'; BLUE=$'\e[34m'; GREY=$'\e[90m'; WHITE=$'\e[97m'

GLY_OK="✓"; GLY_FAIL="✗"; GLY_WARN="⚠"; GLY_RUN="▸"; GLY_INFO="◆"
GLY_SKIP="↪"; GLY_ASK="?"

TOTAL_STEPS=5
SUDO_PASS="${SUDO_PASS:-kali}"
RESULTS=()
START_TIME=$(date +%s)

# ─── Çerçeve çizimi ────────────────────────────────────────────────────
INNER=70

# Sabit dash şeridi (INNER kadar ─)
DASH_LINE=""
for ((i=0; i<INNER; i++)); do DASH_LINE+="─"; done

# Görünür sütun uzunluğu: ANSI sökülür; UTF-8 codepoint sayısına emoji
# (U+1F300–U+1FAFF) için +1 ekler (terminalde 2 sütun yer kaplar).
vlen() {
  local s
  s=$(printf '%s' "$1" | sed -E $'s/\x1B\\[[0-9;]*[a-zA-Z]//g')
  local n=${#s}
  local extras
  extras=$(printf '%s' "$s" | grep -oP '[\x{1F300}-\x{1FAFF}]' 2>/dev/null | wc -l)
  echo $((n + extras))
}

top_bar() { printf '%s%s╭%s╮%s\n' "$BOLD" "$1" "$DASH_LINE" "$RST"; }
bot_bar() { printf '%s%s╰%s╯%s\n' "$BOLD" "$1" "$DASH_LINE" "$RST"; }

# Tek satır içerik basar; içerik hangi uzunlukta olursa olsun sağ kenara
# kadar boşlukla doldurur ve sağ │ koyar.
boxln() {
  local color="$1" content="$2"
  local clen pad
  clen=$(vlen "$content")
  pad=$((INNER - clen))
  (( pad < 0 )) && pad=0
  printf '%s│%s%s%s%*s%s│%s\n' \
    "$BOLD$color" "$RST" "$content" "$RST" \
    "$pad" "" \
    "$BOLD$color" "$RST"
}

empty() { boxln "$1" ""; }

# Adım açılış başlığı: ╭─[ Adım N/M ]─ Başlık ──...──╮
step_top() {
  local n="$1" title="$2"
  local prefix="─[ Adım $n/$TOTAL_STEPS ]─ $title "
  local plen pad dashes=""
  plen=$(vlen "$prefix")
  pad=$((INNER - plen))
  (( pad < 0 )) && pad=0
  while ((pad-- > 0)); do dashes+="─"; done
  printf '%s%s╭%s%s╮%s\n' "$BOLD" "$MAGENTA" "$prefix" "$dashes" "$RST"
}

# ─── UI bloklar ────────────────────────────────────────────────────────
banner() {
  printf '\n'
  top_bar "$CYAN"
  empty "$CYAN"
  boxln "$CYAN" "   ${BOLD}${WHITE}🚀  MEBKALI${RST} — Kali için MEB ağı yapılandırma yardımcısı"
  boxln "$CYAN" "       ${DIM}MEB ağında kurulu Kali'yi adım adım kullanılır hale getirir${RST}"
  empty "$CYAN"
  boxln "$CYAN" "   ${GREEN}•${RST} ${BOLD}${TOTAL_STEPS} ardışık adım${RST} — her biri MEB ağının bir engelini aşar"
  if (( AUTO_YES )); then
    boxln "$CYAN" "   ${GREEN}•${RST} Tüm adımlar onaysız çalışacak ${DIM}(-y)${RST}"
  else
    boxln "$CYAN" "   ${GREEN}•${RST} Her adımdan önce ne yapacağı anlatılır ve onay alınır"
  fi
  boxln "$CYAN" "   ${GREEN}•${RST} Yeniden çalıştırılabilir — yarıda kesilse de baştan başlanabilir"
  empty "$CYAN"
  if ! (( AUTO_YES )); then
    boxln "$CYAN" "   ${DIM}İpucu:${RST} onay sorularında ${BOLD}E${RST} = evet, ${BOLD}h${RST} = atla, ${BOLD}q${RST} = çıkış"
    boxln "$CYAN" "   ${DIM}Tümünü otomatik onaylamak için:${RST} ${BOLD}bash mebkali.sh -y${RST}"
    empty "$CYAN"
  fi
  bot_bar "$CYAN"
  printf '\n'
}

step_open() {
  local n="$1" title="$2"
  printf '\n'
  step_top "$n" "$title"
  empty "$MAGENTA"
}

step_engel() {
  local heading="${1:-Aşılacak sorun}"
  boxln "$MAGENTA" "  ${BOLD}${YELLOW}${GLY_WARN}${RST}${BOLD} ${heading}${RST}"
  while IFS= read -r line; do
    boxln "$MAGENTA" "    ${DIM}${line}${RST}"
  done
  empty "$MAGENTA"
}

step_cozum() {
  local heading="${1:-Bu adımın çözümü}"
  boxln "$MAGENTA" "  ${BOLD}${GREEN}${GLY_OK}${RST}${BOLD} ${heading}${RST}"
  while IFS= read -r line; do
    boxln "$MAGENTA" "    ${line}"
  done
  empty "$MAGENTA"
  bot_bar "$MAGENTA"
}

# ─── Onay sorgusu ──────────────────────────────────────────────────────
ask_confirm() {
  if (( AUTO_YES )); then
    printf '  %s%s%s Otomatik onay (-y)%s\n' "$DIM$GREEN" "$GLY_OK" "$RST" "$RST"
    return 0
  fi
  local ans
  while true; do
    printf '  %s%s%s Bu adımı uygulayalım mı? %s[E/h/q]%s: ' \
      "$BOLD$CYAN" "$GLY_ASK" "$RST" "$BOLD" "$RST"
    if ! IFS= read -r ans </dev/tty 2>/dev/null; then
      printf '%s(stdin yok — otomatik evet)%s\n' "$DIM" "$RST"
      return 0
    fi
    ans="${ans,,}"
    case "$ans" in
      ""|e|evet|y|yes) return 0 ;;
      h|hayir|hayır|n|no|s|skip) return 1 ;;
      q|quit|exit|cikis|çıkış)
        printf '  %s%s%s Kullanıcı çıkışı — bu noktaya kadar olan adımlar uygulandı.%s\n' \
          "$YELLOW" "$GLY_WARN" "$RST" "$RST"
        celebrate
        exit 130
        ;;
      *) printf '  %sLütfen E (evet) / h (atla) / q (çıkış) yazın.%s\n' "$DIM" "$RST" ;;
    esac
  done
}

# ─── Alt betik çalıştırma ──────────────────────────────────────────────
run_script() {
  local script="$1" rc t0 t1 dur
  t0=$(date +%s)
  printf '  %s%s%s %ssudo bash %s/%s%s\n' "$CYAN" "$GLY_RUN" "$RST" "$BOLD" "$SCRIPT_DIR_NAME" "$script" "$RST"
  printf '  %s┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄%s\n' "$GREY" "$RST"
  sudo -n bash "$(pwd)/$script" 2>&1 | sed -e "s|^|  ${GREY}│${RST} |"
  rc=${PIPESTATUS[0]}
  printf '  %s┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄%s\n' "$GREY" "$RST"
  t1=$(date +%s); dur=$((t1 - t0))
  if [[ $rc -eq 0 ]]; then
    printf '  %s%s %s tamamlandı%s %s(%ds)%s\n' "$BOLD$GREEN" "$GLY_OK" "$script" "$RST" "$DIM" "$dur" "$RST"
    RESULTS+=("OK:$script:$dur")
  else
    printf '  %s%s %s BAŞARISIZ%s %s(rc=%d, %ds)%s\n' "$BOLD$RED" "$GLY_FAIL" "$script" "$RST" "$DIM" "$rc" "$dur" "$RST"
    RESULTS+=("FAIL:$script:$dur")
  fi
  return $rc
}

skip_step() {
  local script="$1"
  printf '  %s%s%s %s atlandı.%s\n' "$YELLOW" "$GLY_SKIP" "$RST" "$script" "$RST"
  RESULTS+=("SKIP:$script:0")
}

# ─── Tebrik / özet ─────────────────────────────────────────────────────
celebrate() {
  local total=$(( $(date +%s) - START_TIME ))
  local passed=0 failed=0 skipped=0
  for r in "${RESULTS[@]}"; do
    case "$r" in
      OK:*)   passed=$((passed+1)) ;;
      FAIL:*) failed=$((failed+1)) ;;
      SKIP:*) skipped=$((skipped+1)) ;;
    esac
  done
  printf '\n'
  if (( failed == 0 )) && (( passed > 0 )); then
    top_bar "$GREEN"
    empty "$GREEN"
    boxln "$GREEN" "   ${BOLD}${WHITE}🎉  TEBRİKLER!${RST}"
    empty "$GREEN"
    boxln "$GREEN" "   Kali makineniz ${BOLD}${passed} adımda${RST} ve ${BOLD}${total} saniyede${RST} yapılandırıldı:"
    if (( skipped > 0 )); then
      boxln "$GREEN" "   ${DIM}(${skipped} adım atlandı)${RST}"
    fi
    empty "$GREEN"
    for r in "${RESULTS[@]}"; do
      case "$r" in
        OK:01-*)   boxln "$GREEN" "     ${GREEN}${GLY_OK}${RST}  MEB kök sertifikasının sisteme tanıtılması" ;;
        OK:02-*)   boxln "$GREEN" "     ${GREEN}${GLY_OK}${RST}  Apt paket sunucusu (yedekli, çalışan)" ;;
        OK:03-*)   boxln "$GREEN" "     ${GREEN}${GLY_OK}${RST}  Türkçe yerel ayarlar + Q klavye" ;;
        OK:04-*)   boxln "$GREEN" "     ${GREEN}${GLY_OK}${RST}  Saat dilimi + zaman senkronizasyonu" ;;
        OK:05-*)   boxln "$GREEN" "     ${GREEN}${GLY_OK}${RST}  VirtualBox ana makine paylaşımı" ;;
        SKIP:01-*) boxln "$GREEN" "     ${YELLOW}${GLY_SKIP}${RST}  MEB sertifika adımı atlandı" ;;
        SKIP:02-*) boxln "$GREEN" "     ${YELLOW}${GLY_SKIP}${RST}  Apt paket sunucusu adımı atlandı" ;;
        SKIP:03-*) boxln "$GREEN" "     ${YELLOW}${GLY_SKIP}${RST}  Türkçe yerel ayar/klavye adımı atlandı" ;;
        SKIP:04-*) boxln "$GREEN" "     ${YELLOW}${GLY_SKIP}${RST}  Saat/zaman senkronizasyon adımı atlandı" ;;
        SKIP:05-*) boxln "$GREEN" "     ${YELLOW}${GLY_SKIP}${RST}  VirtualBox paylaşım adımı atlandı" ;;
      esac
    done
    empty "$GREEN"
    boxln "$GREEN" "   ${BOLD}${WHITE}Sıradaki manuel adımlar:${RST}"
    boxln "$GREEN" "     ${CYAN}•${RST} Bir kez oturumu kapat → aç (yerel ayar + klavye + grup)"
    boxln "$GREEN" "     ${CYAN}•${RST} Ana makinede VirtualBox ayarı: pano + paylaşılan klasör"
    boxln "$GREEN" "       ${DIM}komut için: bash 05-vbox-host-paylasim.sh --print-host-cmds${RST}"
    empty "$GREEN"
    bot_bar "$GREEN"
    printf '\n'
  elif (( failed > 0 )); then
    top_bar "$RED"
    empty "$RED"
    boxln "$RED" "   ${BOLD}${GLY_FAIL}${RST} ${BOLD}${failed} adım başarısız${RST}"
    boxln "$RED" "   Hatayı düzeltip yeniden çalıştırın."
    boxln "$RED" "   ${DIM}(Betikler yeniden çalıştırılabilir; var olanı tekrar uygulamaz)${RST}"
    empty "$RED"
    bot_bar "$RED"
    printf '\n'
  else
    top_bar "$YELLOW"
    empty "$YELLOW"
    boxln "$YELLOW" "   ${BOLD}${GLY_WARN} Hiçbir adım uygulanmadı.${RST}"
    empty "$YELLOW"
    bot_bar "$YELLOW"
    printf '\n'
  fi
}

# ─── Sudo erişimi ──────────────────────────────────────────────────────
prep_sudo() {
  printf '%s%s%s Sudo erişimi sağlanıyor...%s\n' "$CYAN" "$GLY_INFO" "$RST" "$RST"
  if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
    printf '%s%s%s Sudo şifresi reddedildi. SUDO_PASS ortam değişkeniyle veya stdin ile doğru şifreyi ver.%s\n' \
      "$RED" "$GLY_FAIL" "$RST" "$RST"
    exit 1
  fi
  ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) &
  SUDO_KEEPER=$!
  trap 'kill "$SUDO_KEEPER" 2>/dev/null || true' EXIT
  printf '  %s%s%s Sudo etkin (arka planda canlı tutuluyor)%s\n' "$GREEN" "$GLY_OK" "$RST" "$RST"
}

# ─── Adım tanımları ────────────────────────────────────────────────────

step1() {
  step_open 1 "MEB kök sertifikasının sisteme tanıtılması"
  step_engel "Sertifika doğrulama hataları" <<'ENGEL'
MEB ağı, internete giden tüm güvenli (HTTPS) bağlantıları kendi
kök sertifikasıyla yeniden imzalıyor. Kali bu sertifikayı
tanımadığı için curl, git, apt, Firefox, Python — hiçbir araç
internete ulaşamıyor; "sertifika doğrulanamadı" hatası alıyor.
ENGEL
  step_cozum "Sertifika 4 ayrı güven deposuna eklenecek" <<'COZUM'
MEB kök sertifikası 4 farklı güven deposuna ekleniyor: sistem
geneli sertifika havuzu, Firefox'un sertifika veritabanı,
Chromium'un sertifika veritabanı ve Python'un kendi denetimi.
Python'un katı sertifika kontrolü MEB sertifikasını kabul etsin
diye bir yama da bırakılıyor (paket güncellemelerinden
etkilenmeyecek konumda). Kabukta SSL_CERT_FILE,
REQUESTS_CA_BUNDLE, GIT_SSL_CAINFO gibi ortam değişkenleri
sistem havuzuna yönlendiriliyor.
COZUM
  if ask_confirm; then
    run_script "01-mitm-cert-trust.sh"
  else
    skip_step "01-mitm-cert-trust.sh"
    return 0
  fi
}

step2() {
  step_open 2 "Apt paket sunucusu (yedekli, çalışan)"
  step_engel "Paket sunucusu erişilemez olabilir" <<'ENGEL'
Kali kurulduğunda varsayılan paket sunucusu (mirror) o an
yanıt vermiyor olabilir; tek bir sunucuya güvenmek riskli.
Sunucu erişilemez olduğunda apt güncellemesi bile yapılamıyor.
ENGEL
  step_cozum "11 yedekli sunucu arasından çalışan ilkine geçilecek" <<'COZUM'
11 farklı yedek paket sunucusu sırayla denenir; ilk yanıt veren
seçilir. Mevcut yapılandırma zaman damgalı yedeklenir; bir
sorun olursa otomatik geri alınır. Sadece kali-rolling
satırlarına dokunulur, eklenti depolar etkilenmez.
COZUM
  if ask_confirm; then
    run_script "02-apt-mirror-fix.sh"
  else
    skip_step "02-apt-mirror-fix.sh"
    return 0
  fi
}

step3() {
  step_open 3 "Türkçe yerel ayarlar + Q klavye"
  step_engel "Türkçe karakter ve klavye düzeni eksikliği" <<'ENGEL'
Kali, Amerikan İngilizcesi yerel ayarıyla geliyor; Türkçe
karakterler yazılamıyor, "İ"/"i" büyük-küçük dönüşümü ve
Türkçe sıralama yanlış. (Bu adımda doğrudan MEB-bağlantılı
bir engel yok — Türkiye uyum açığı.)
ENGEL
  step_cozum "tr_TR.UTF-8 + Q klavye 3 katmanda kurulacak" <<'COZUM'
Türkçe yerel ayarlar (tr_TR.UTF-8) etkinleştirilir. Karma
yapı: arayüz dili İngilizce kalır, ama karakter sınıflandırma
ve sıralama Türkçe (büyük/küçük harf "İ" doğru çalışır).
Türkçe Q klavye 3 katmanda kurulur: terminal (TTY), grafik
ortam (X11) ve oturum açma ekranı (LightDM).
COZUM
  if ask_confirm; then
    run_script "03-turkce-locale-keyboard.sh"
  else
    skip_step "03-turkce-locale-keyboard.sh"
    return 0
  fi
}

step4() {
  step_open 4 "Saat dilimi + zaman senkronizasyonu"
  step_engel "Yanlış saat dilimi ve yedeksiz NTP" <<'ENGEL'
Sanal makinenin saat dilimi varsayılan olarak yanlış olabiliyor;
zaman ayarı için tek bir sunucuya güvenmek yedeksiz. NTP
trafiği bazı sıkı güvenlik duvarlarında engellenebilir.
ENGEL
  step_cozum "Europe/Istanbul + 4+6 yedekli NTP sunucusu yazılacak" <<'COZUM'
Saat dilimi Europe/Istanbul yapılır (yaz/kış saati değişimleri
otomatik takip edilir). systemd-timesyncd'ye 4 birincil + 6
yedek zaman sunucusu yazılır (Türkiye, Cloudflare, Google,
Debian, NIST). Donanım saati UTC'de tutulur (Windows ile çift
kurulumda saat karışmaz). Saat ekranda 24 saat biçimde gösterilir.
COZUM
  if ask_confirm; then
    run_script "04-ntp-tz-format.sh"
  else
    skip_step "04-ntp-tz-format.sh"
    return 0
  fi
}

step5() {
  step_open 5 "VirtualBox ana makine paylaşımı (pano + dosya)"
  step_engel "Ağ üzerinden dosya/pano paylaşımı MEB tarafından görülür" <<'ENGEL'
Sanal makine ile ana bilgisayar arasında dosya/pano paylaşımı
için ağ tabanlı yöntemler (SSH, SCP, web yükleme) kullanılırsa,
paketler MEB ağından geçer: gözetim, içerik filtreleme ve
protokol engelleri risktir.
ENGEL
  step_cozum "Hipervizör IPC üzerinden ağ-dışı paylaşım kurulacak" <<'COZUM'
VirtualBox'ın hipervizör IPC altyapısı kullanılır — paketler
ağdan hiç çıkmaz, MEB'in görüş alanı dışındadır. Pano,
sürükle-bırak ve paylaşılan klasör destekleri doğrulanır;
gerekli kullanıcı grubu ve çekirdek modülleri eklenir. Ana
makine tarafındaki ayarlar misafirden otomatize edilemez —
gerekli VBoxManage komutları ekrana yazdırılır.
COZUM
  if ask_confirm; then
    run_script "05-vbox-host-paylasim.sh"
  else
    skip_step "05-vbox-host-paylasim.sh"
    return 0
  fi
}

# ─── Ana akış ──────────────────────────────────────────────────────────
banner
prep_sudo

step1 || { celebrate; exit 1; }
step2 || { celebrate; exit 1; }
step3 || { celebrate; exit 1; }
step4 || { celebrate; exit 1; }
step5 || { celebrate; exit 1; }
celebrate
