#!/usr/bin/env bash
# mebkali.sh
# Kali (MEB MITM/firewall arkasında) için adım adım yapılandırma orkestratörü.
# 6 alt-betiği sırayla çağırır; her adımda önce engeli ve çözümü anlatır,
# sonra kullanıcıdan onay alır.
#
# Çalıştırma:
#   bash mebkali.sh           # interaktif (her adımda onay)
#   bash mebkali.sh -y        # tüm adımları onaysız (otomatik evet)
#   SUDO_PASS=kali bash ...   # sudo şifresini env ile geçir (default "kali")

set -uo pipefail

# Box çizimi ve genişlik hesabı için UTF-8 locale gerekli
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_NAME="$(basename "$(pwd)")"   # GitHub'dan farklı isimle clone edilirse de doğru görünür

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
  SUDO_PASS    Sudo şifresi (default: "kali"). Sudo prompt'u atlamak için.
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

TOTAL_STEPS=6
SUDO_PASS="${SUDO_PASS:-kali}"
RESULTS=()
START_TIME=$(date +%s)

# ─── UI yardımcıları (sağ kenar çizgisi YOK — emoji/TR genişlik sorunu olmaz) ─
banner() {
  printf '\n'
  printf '%s%s╭──────────────────────────────────────────────────────────────────────%s\n' "$BOLD" "$CYAN" "$RST"
  printf '%s%s│%s\n' "$BOLD" "$CYAN" "$RST"
  printf '%s%s│%s   %s🚀  MEBKALI%s — Kali Bootstrap\n' "$BOLD" "$CYAN" "$RST" "$BOLD$WHITE" "$RST"
  printf '%s%s│%s       %sMEB MITM / firewall arkasında adım adım yapılandırma%s\n' "$BOLD" "$CYAN" "$RST" "$DIM" "$RST"
  printf '%s%s│%s\n' "$BOLD" "$CYAN" "$RST"
  printf '%s%s│%s   %s•%s %s%d ardışık adım%s — her biri MEB/firewall'\''un bir engelini aşar\n' \
    "$BOLD" "$CYAN" "$RST" "$GREEN" "$RST" "$BOLD" "$TOTAL_STEPS" "$RST"
  if (( AUTO_YES )); then
    printf '%s%s│%s   %s•%s Tüm adımlar onaysız çalışacak %s(-y)%s\n' \
      "$BOLD" "$CYAN" "$RST" "$GREEN" "$RST" "$DIM" "$RST"
  else
    printf '%s%s│%s   %s•%s Her adımdan önce ne yapacağı anlatılır ve onay alınır\n' \
      "$BOLD" "$CYAN" "$RST" "$GREEN" "$RST"
  fi
  printf '%s%s│%s   %s•%s Idempotent — yarıda kesilse de yeniden başlatılabilir\n' \
    "$BOLD" "$CYAN" "$RST" "$GREEN" "$RST"
  printf '%s%s│%s\n' "$BOLD" "$CYAN" "$RST"
  if ! (( AUTO_YES )); then
    printf '%s%s│%s   %sİpucu:%s onay sorularında %sE%s = evet, %sh%s = atla, %sq%s = çıkış\n' \
      "$BOLD" "$CYAN" "$RST" "$DIM" "$RST" "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
    printf '%s%s│%s   %sTümünü otomatik onaylamak için: %s%sbash mebkali.sh -y%s\n' \
      "$BOLD" "$CYAN" "$RST" "$DIM" "$RST" "$BOLD" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$CYAN" "$RST"
  fi
  printf '%s%s╰──────────────────────────────────────────────────────────────────────%s\n\n' "$BOLD" "$CYAN" "$RST"
}

step_open() {
  local n="$1" title="$2"
  printf '\n'
  printf '%s%s╭─[ Adım %d/%d ]─ %s%s\n'      "$BOLD" "$MAGENTA" "$n" "$TOTAL_STEPS" "$title" "$RST"
  printf '%s%s│%s\n'                          "$BOLD" "$MAGENTA" "$RST"
}

step_engel() {
  printf '%s%s│%s  %s%s%s MEB engeli%s\n' "$BOLD" "$MAGENTA" "$RST" "$BOLD" "$YELLOW" "$GLY_WARN" "$RST"
  while IFS= read -r line; do
    printf '%s%s│%s    %s%s%s\n' "$BOLD" "$MAGENTA" "$RST" "$DIM" "$line" "$RST"
  done
  printf '%s%s│%s\n' "$BOLD" "$MAGENTA" "$RST"
}

step_cozum() {
  printf '%s%s│%s  %s%s%s Bu adımın çözümü%s\n' "$BOLD" "$MAGENTA" "$RST" "$BOLD" "$GREEN" "$GLY_OK" "$RST"
  while IFS= read -r line; do
    printf '%s%s│%s    %s\n' "$BOLD" "$MAGENTA" "$RST" "$line"
  done
  printf '%s%s│%s\n' "$BOLD" "$MAGENTA" "$RST"
  printf '%s%s╰─%s\n' "$BOLD" "$MAGENTA" "$RST"
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
    printf '%s%s╭──────────────────────────────────────────────────────────────────────%s\n' "$BOLD" "$GREEN" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$GREEN" "$RST"
    printf '%s%s│%s   %s🎉  TEBRİKLER!%s\n' "$BOLD" "$GREEN" "$RST" "$BOLD$WHITE" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$GREEN" "$RST"
    printf '%s%s│%s   Kali makineniz %s%d adımda%s ve %s%d saniyede%s yapılandırıldı:\n' \
      "$BOLD" "$GREEN" "$RST" "$BOLD" "$passed" "$RST" "$BOLD" "$total" "$RST"
    if (( skipped > 0 )); then
      printf '%s%s│%s   %s(%d adım atlandı)%s\n' "$BOLD" "$GREEN" "$RST" "$DIM" "$skipped" "$RST"
    fi
    printf '%s%s│%s\n' "$BOLD" "$GREEN" "$RST"
    for r in "${RESULTS[@]}"; do
      case "$r" in
        OK:01-*)   printf '%s%s│%s     %s✓%s  MEB MITM kök sertifika güveni\n'              "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        OK:02-*)   printf '%s%s│%s     %s✓%s  Apt mirror yedekli, çalışıyor\n'              "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        OK:03-*)   printf '%s%s│%s     %s✓%s  Türkçe locale + Q klavye (3 katman)\n'        "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        OK:04-*)   printf '%s%s│%s     %s✓%s  Saat dilimi Europe/Istanbul + yedekli NTP\n'  "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        OK:05-*)   printf '%s%s│%s     %s✓%s  VBox host paylaşım altyapısı (pano + dosya)\n' "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        OK:06-*)   printf '%s%s│%s     %s✓%s  HTTPS-only firewall bypass (whois→RDAP)\n'    "$BOLD" "$GREEN" "$RST" "$GREEN" "$RST" ;;
        SKIP:01-*) printf '%s%s│%s     %s↪%s  MEB sertifika adımı atlandı\n'                "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
        SKIP:02-*) printf '%s%s│%s     %s↪%s  Apt mirror adımı atlandı\n'                   "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
        SKIP:03-*) printf '%s%s│%s     %s↪%s  Türkçe locale/klavye adımı atlandı\n'         "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
        SKIP:04-*) printf '%s%s│%s     %s↪%s  Saat/NTP adımı atlandı\n'                     "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
        SKIP:05-*) printf '%s%s│%s     %s↪%s  VBox paylaşım adımı atlandı\n'                "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
        SKIP:06-*) printf '%s%s│%s     %s↪%s  RDAP whois adımı atlandı\n'                   "$BOLD" "$GREEN" "$RST" "$YELLOW" "$RST" ;;
      esac
    done
    printf '%s%s│%s\n' "$BOLD" "$GREEN" "$RST"
    printf '%s%s│%s   %sSıradaki manuel adımlar:%s\n' "$BOLD" "$GREEN" "$RST" "$BOLD$WHITE" "$RST"
    printf '%s%s│%s     %s•%s Bir kez logout → login (locale + Q klavye + grup üyeliği)\n' \
      "$BOLD" "$GREEN" "$RST" "$CYAN" "$RST"
    printf '%s%s│%s     %s•%s Host VBox: Bidirectional clipboard + Shared Folder ayarla\n' \
      "$BOLD" "$GREEN" "$RST" "$CYAN" "$RST"
    printf '%s%s│%s       %s(talimat: bash %s/05-vbox-host-paylasim.sh --print-host-cmds)%s\n' \
      "$BOLD" "$GREEN" "$RST" "$DIM" "$SCRIPT_DIR_NAME" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$GREEN" "$RST"
    printf '%s%s╰──────────────────────────────────────────────────────────────────────%s\n\n' "$BOLD" "$GREEN" "$RST"
  elif (( failed > 0 )); then
    printf '%s%s╭──────────────────────────────────────────────────────────────────────%s\n' "$BOLD" "$RED" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$RED" "$RST"
    printf '%s%s│%s   %s%s %d adım başarısız%s\n' "$BOLD" "$RED" "$RST" "$BOLD" "$GLY_FAIL" "$failed" "$RST"
    printf '%s%s│%s   Hatayı düzeltip yeniden çalıştırın (idempotent).\n' "$BOLD" "$RED" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$RED" "$RST"
    printf '%s%s╰──────────────────────────────────────────────────────────────────────%s\n\n' "$BOLD" "$RED" "$RST"
  else
    printf '%s%s╭──────────────────────────────────────────────────────────────────────%s\n' "$BOLD" "$YELLOW" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$YELLOW" "$RST"
    printf '%s%s│%s   %s%s Hiçbir adım uygulanmadı.%s\n' "$BOLD" "$YELLOW" "$RST" "$BOLD" "$GLY_WARN" "$RST"
    printf '%s%s│%s\n' "$BOLD" "$YELLOW" "$RST"
    printf '%s%s╰──────────────────────────────────────────────────────────────────────%s\n\n' "$BOLD" "$YELLOW" "$RST"
  fi
}

# ─── Sudo erişimi ──────────────────────────────────────────────────────
prep_sudo() {
  printf '%s%s%s Sudo erişimi sağlanıyor...%s\n' "$CYAN" "$GLY_INFO" "$RST" "$RST"
  if ! echo "$SUDO_PASS" | sudo -S -v 2>/dev/null; then
    printf '%s%s%s Sudo şifresi reddedildi. SUDO_PASS env veya stdin ile doğru şifreyi ver.%s\n' \
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
  step_open 1 "MEB MITM kök sertifika güveni"
  step_engel <<'ENGEL'
MEB firewall TLS bağlantılarını intercept edip kendi 'fatihca' kök
sertifikasıyla yeniden imzalıyor. Sistem bu kökü güvenli bilmediği için
curl/git/wget/python/firefox/chromium TÜM HTTPS bağlantılarında
'CERTIFICATE_VERIFY_FAILED' hatası alır. Apt update bile imkansız.
ENGEL
  step_cozum <<'COZUM'
'fatihca' kökü 4 farklı trust deposuna eklenir: (1) sistem CA bundle
(curl/git/wget/openssl), (2) p11-kit shared trust, (3) Firefox NSS DB,
(4) Chromium NSS DB. Python 3.13'ün VERIFY_X509_STRICT bayrağı MEB'in
eksik AKI extension'ıyla çakıştığı için ssl ve urllib3'e
/usr/lib/python3/dist-packages/'a versiyonsuz, apt-upgrade-proof bir
yama konulur. /etc/profile.d/meb-ca.sh ile SSL_CERT_FILE,
REQUESTS_CA_BUNDLE, NODE_EXTRA_CA_CERTS, PIP_CERT, GIT_SSL_CAINFO vb.
tüm araç env vars sistem CA bundle'ına yönlendirilir.
COZUM
  if ask_confirm; then
    run_script "01-mitm-cert-trust.sh"
  else
    skip_step "01-mitm-cert-trust.sh"
    return 0
  fi
}

step2() {
  step_open 2 "Apt mirror yedekli HTTPS yönlendirmesi"
  step_engel <<'ENGEL'
Default mirror http.kali.org HTTP/503 dönüyor — apt update, paket
kurulumu yapılamıyor. Tek bir mirror'a güvenmek tek nokta arızasıdır;
betik çalıştığı tarihte o da erişilemez olabilir.
ENGEL
  step_cozum <<'COZUM'
11 aday mirror sırayla HTTPS InRelease testinden geçer (kali.download
CDN ilk; GARR-IT, NetCologne, archive-1..3, Dalhousie, KAIST, FU Berlin,
http.kali.org). İlk 200 dönen seçilir. /etc/apt/sources.list zaman
damgalı yedeklenir; awk ile sadece kali-rolling deb satırlarındaki URL
değiştirilir (3rd party PPA'lara dokunulmaz). apt update başarısızsa
otomatik revert.
COZUM
  if ask_confirm; then
    run_script "02-apt-mirror-fix.sh"
  else
    skip_step "02-apt-mirror-fix.sh"
    return 0
  fi
}

step3() {
  step_open 3 "Türkçe locale + Q klavye (3 katman)"
  step_engel <<'ENGEL'
Default Kali en_US locale + US klavye. Türkçe karakterler yazılamıyor;
yazılsa bile 'i'/'I'/'İ' büyük-küçük dönüşümü ve Türkçe sıralama
yanlış. (Bu adımda doğrudan MEB-bağlantılı bir engel yok — Kali default
yapılandırmasının üzerinden gelinmesi gereken bir Türkiye-uyum açığı.)
ENGEL
  step_cozum <<'COZUM'
locale-gen ile tr_TR.UTF-8 derlenir; hibrit ayar: LANG=en_US.UTF-8 +
LC_CTYPE/COLLATE/TIME=tr_TR.UTF-8 (arayüz/loglar İngilizce, Türkçe
karakter sınıflandırma doğru). Klavye için sistemd-native localectl
set-x11-keymap tr + manuel /etc/default/keyboard yazımı (Debian
peculiarity). TTY için /etc/vconsole.conf KEYMAP=trq. XFCE per-user
override temizlenir, çalışan oturuma anında setxkbmap uygulanır.
LightDM giriş ekranı /etc/default/keyboard'u zaten okur.
COZUM
  if ask_confirm; then
    run_script "03-turkce-locale-keyboard.sh"
  else
    skip_step "03-turkce-locale-keyboard.sh"
    return 0
  fi
}

step4() {
  step_open 4 "Saat dilimi Europe/Istanbul + yedekli NTP + 24h"
  step_engel <<'ENGEL'
VM default timezone America/New_York → 7 saat fark. NTP UDP/123 başka
HTTPS-dışı portlar gibi MEB tarafından engellenebilirdi; testlerde açık
çıktı ama tek bir NTP havuzuna güvenmek yedeksizdir.
ENGEL
  step_cozum <<'COZUM'
Timezone Europe/Istanbul'a ayarlanır (IANA tzdata Türkiye'nin DST
kararlarını otomatik takip eder; gelecekteki olası değişiklikler apt
upgrade ile gelir). systemd-timesyncd'a 4 primary + 6 fallback NTP
sunucu yazılır (TR pool, Cloudflare anycast, Debian, Google, NIST...).
Aktif sunucu çoğu zaman 0.tr.pool.ntp.org. RTC UTC'de tutulur (dual-boot
Windows ile karışmaz). XFCE saat plugin formatı %R (24-saat sabit).
COZUM
  if ask_confirm; then
    run_script "04-ntp-tz-format.sh"
  else
    skip_step "04-ntp-tz-format.sh"
    return 0
  fi
}

step5() {
  step_open 5 "VirtualBox host paylaşım (hipervizör IPC)"
  step_engel <<'ENGEL'
Host (siz) ile guest (Kali) arası dosya/pano paylaşımı için ağ tabanlı
yöntemler (SSH, SCP, SMB, web) seçilseydi, trafik MEB firewall görüş
alanına girerdi: gözetim, içerik filtreleme ve protokol blokları
risktir.
ENGEL
  step_cozum <<'COZUM'
VirtualBox Guest Additions hipervizör IPC kullanır — paketler ağdan
hiç çıkmaz, MEB'in görüş alanı dışındadır. clipboard/draganddrop/seamless
daemon'ları doğrulanır; vboxsf grubu ve kernel modülleri idempotent
garantilenir; xclip + xsel kurulur. Host VM ayarlarını yapmak için
VBoxManage komutları ve GUI talimatları yazdırılır (host-side ayarları
guest'ten otomatize edilemez). --test-clipboard ile iki yönlü pano
testi sonradan çalıştırılabilir.
COZUM
  if ask_confirm; then
    run_script "05-vbox-host-paylasim.sh"
  else
    skip_step "05-vbox-host-paylasim.sh"
    return 0
  fi
}

step6() {
  step_open 6 "MEB firewall HTTPS-only bypass (whois → RDAP)"
  step_engel <<'ENGEL'
MEB firewall yalnızca TCP/443 (HTTPS) ve TCP/80 (HTTP) ile MEB DNS'i
(195.175.37.137:53) açık tutuyor. Diğer her şey ya açık görünüyor ama
bloklu (whois 43, AXFR 53/TCP) ya da tamamen bloke (8.8.8.8 UDP/53 vb).
whois/dnsenum/theHarvester'in çakıldığı ortak nokta: HTTPS dışı out-band
protokollere bel bağlamaları.
ENGEL
  step_cozum <<'COZUM'
whois için RDAP HTTPS muadili (port 443) bir wrapper /usr/local/bin/
whois'a kurulur. 3 yedekli RDAP sunucusu (rdap.org, rdap.verisign.com,
rdap.iana.org) sırayla denenir; JSON yanıt jq ile klasik whois benzeri
text'e dönüştürülür. theHarvester ve dnsenum'un çakılma sebepleri
whois'tan farklı (DDG MITM intercept, AXFR firewall) — onlar için
bilgilendirici notlar basılır: theHarvester için engine değişimi
(-b bing/crtsh/otx); dnsenum için --noreverse ya da dnsrecon -t std,brt
alternatifi.
COZUM
  if ask_confirm; then
    run_script "06-firewall-bypass-rdap.sh"
  else
    skip_step "06-firewall-bypass-rdap.sh"
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
step6 || { celebrate; exit 1; }
celebrate
