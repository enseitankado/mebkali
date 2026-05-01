#!/usr/bin/env bash
# 06-firewall-bypass-rdap.sh
# MEB (HTTPS-only) firewall arkasında çalışan whois ve diğer dış-port araçları
# için ortak nedeni teşhis eder ve whois'i RDAP HTTPS muadiline yönlendirir.
#
# Çalıştırma:
#   sudo bash 06-firewall-bypass-rdap.sh             # kurulum + teşhis
#   sudo bash 06-firewall-bypass-rdap.sh --diagnose  # sadece teşhis
#   sudo bash 06-firewall-bypass-rdap.sh --revert    # wrapper'ı kaldır
#
# Tespit edilen ortak neden:
#   MEB firewall TCP/443 (HTTPS) ve TCP/80 dışındaki dış protokolleri reddeder.
#   - whois (TCP/43): bağlantı kurulmuş gibi görünür ama veri akışı kesilir
#   - dig 8.8.8.8 (UDP/53 dış): tamamen bloke
#   - DNS AXFR (TCP/53): timeout
#   - theHarvester (HTTPS) bazen MITM tarafından search engine yanıtı
#     bozulduğu için çakılır
#
# Çözüm:
#   1. whois -> RDAP (HTTPS, port 443) yönlendirmesi: tüm sorgular hipervizörden
#      MEB firewall üzerinden HTTPS olarak geçer; cert zinciri kuruludur.
#   2. theHarvester/dnsenum gibi araçlar için tavsiye notları (script sonunda).

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }
hl()   { printf "%s%s%s\n"     "$CYAN"   "$*" "$NC"; }

WRAPPER="/usr/local/bin/whois"
ORIG_WHOIS="/usr/bin/whois"

run_diagnosis() {
  hl "━━━ Network kısıt teşhisi ━━━"
  printf "  %-45s " "TCP/443 (HTTPS)"
  timeout 5 bash -c '</dev/tcp/example.com/443' 2>/dev/null && echo "${GREEN}OPEN${NC}" || echo "${RED}KAPALI${NC}"
  printf "  %-45s " "TCP/43 (whois protokolü)"
  if timeout 5 bash -c '</dev/tcp/whois.iana.org/43' 2>/dev/null; then
    # Port açık görünüyor — gerçek whois çalışıyor mu?
    if timeout 6 whois -h whois.iana.org example.com 2>/dev/null | grep -q "domain:"; then
      echo "${GREEN}ÇALIŞIYOR${NC}"
    else
      echo "${YELLOW}port OPEN ama veri akışı KESİLİYOR (MITM proxy)${NC}"
    fi
  else
    echo "${RED}KAPALI${NC}"
  fi
  printf "  %-45s " "UDP/53 harici (dig @8.8.8.8)"
  if timeout 5 dig +short +time=3 +tries=1 @8.8.8.8 example.com >/dev/null 2>&1; then
    echo "${GREEN}OPEN${NC}"
  else
    echo "${RED}KAPALI${NC}"
  fi
  printf "  %-45s " "UDP/53 yerel resolver"
  if timeout 3 dig +short example.com >/dev/null 2>&1; then
    echo "${GREEN}OPEN${NC}"
  else
    echo "${RED}KAPALI${NC}"
  fi
  printf "  %-45s " "TCP/53 (DNS over TCP / AXFR)"
  timeout 5 bash -c '</dev/tcp/8.8.8.8/53' 2>/dev/null && echo "${GREEN}OPEN${NC}" || echo "${RED}KAPALI${NC}"
  printf "  %-45s " "RDAP HTTPS (rdap.org)"
  source /etc/profile.d/meb-ca.sh 2>/dev/null || true
  CODE="$(curl -sLo /dev/null -w '%{http_code}' --max-time 8 'https://rdap.org/domain/example.com' 2>/dev/null || echo 000)"
  [[ "$CODE" == "200" ]] && echo "${GREEN}OK ($CODE)${NC}" || echo "${RED}HTTP $CODE${NC}"
  echo
  hl "Sonuç: HTTPS dışı protokoller çalışmıyor; çözüm whois -> RDAP yönlendirmesi."
}

case "${1:-}" in
  --diagnose)
    run_diagnosis
    exit 0
    ;;
  --revert)
    [[ $EUID -eq 0 ]] || { err "sudo gerekli"; exit 1; }
    if [[ -L "$WRAPPER" || -f "$WRAPPER" ]]; then
      rm -f "$WRAPPER"
      ok "Wrapper kaldırıldı: $WRAPPER"
    else
      ok "Wrapper zaten yok"
    fi
    exit 0
    ;;
  ""|--install)
    : # default akış
    ;;
  *)
    err "Bilinmeyen argüman: $1"
    err "Kullanım: $0 [--install|--diagnose|--revert]"
    exit 1
    ;;
esac

[[ $EUID -eq 0 ]] || { err "Bu mod root yetkisi gerektirir. sudo bash $0"; exit 1; }

# 1) Teşhis (her install çalışmasında bir kez)
run_diagnosis
echo

# 2) Bağımlılıklar — jq + curl
say "1/3 Bağımlılıklar (jq, curl)..."
NEED=()
command -v jq   >/dev/null 2>&1 || NEED+=("jq")
command -v curl >/dev/null 2>&1 || NEED+=("curl")
if (( ${#NEED[@]} > 0 )); then
  apt-get install -y --no-install-recommends "${NEED[@]}" >/dev/null 2>&1 \
    && ok "Kuruldu: ${NEED[*]}" \
    || { err "Kurulum başarısız (apt çalışıyor mu? 02-apt-mirror-fix.sh)"; exit 1; }
else
  ok "jq, curl mevcut"
fi

# 3) /usr/local/bin/whois wrapper'ı yaz
say "2/3 RDAP-tabanlı whois wrapper'ı /usr/local/bin/whois'a yaz..."
if [[ -f "$WRAPPER" ]] && head -2 "$WRAPPER" 2>/dev/null | grep -qE "rdap-wrapper"; then
  ok "Wrapper zaten kurulu (idempotent)"
else
  cat > "$WRAPPER" <<'WRAP'
#!/usr/bin/env bash
# mebkali-rdap-wrapper
# whois sorgularını RDAP HTTPS muadiline yönlendirir. MEB gibi HTTPS-only
# firewall arkasında klasik TCP/43 whois çalışmadığında devreye girer.
# Argüman ne olursa olsun son token'ı domain veya IP olarak alır.

set -u
DOMAIN=""
ORIG_WHOIS_BIN="/usr/bin/whois"

# Klasik whois argümanlarını parse et — son arg domain/IP olur
for arg in "$@"; do
  case "$arg" in
    -*) ;;  # flag'leri atla
    *)  DOMAIN="$arg" ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Kullanım: whois <domain veya IP>" >&2
  exit 2
fi

# Env'den CA bundle yüklensin (MEB MITM cert için)
[[ -r /etc/profile.d/meb-ca.sh ]] && source /etc/profile.d/meb-ca.sh

# IP mi domain mi tespit et
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$DOMAIN" =~ : ]]; then
  RDAP_PATH="ip/$DOMAIN"
else
  RDAP_PATH="domain/$DOMAIN"
fi

# RDAP sorgu — birden fazla sunucuyu sırayla dene
RDAP_SERVERS=(
  "https://rdap.org"
  "https://rdap.verisign.com/com/v1"   # com/net direkt
  "https://rdap.iana.org"              # IANA aggregator
)

RESULT=""
for srv in "${RDAP_SERVERS[@]}"; do
  RESULT="$(curl -sfL --max-time 12 \
    -H 'Accept: application/rdap+json' \
    "$srv/$RDAP_PATH" 2>/dev/null)" && break
  RESULT=""
done

if [[ -z "$RESULT" ]]; then
  echo "[wrapper] RDAP sorgular başarısız oldu, klasik whois fallback deneniyor..." >&2
  if [[ -x "$ORIG_WHOIS_BIN" ]]; then
    exec "$ORIG_WHOIS_BIN" "$@"
  else
    echo "[wrapper] Klasik whois da yok ($ORIG_WHOIS_BIN)" >&2
    exit 3
  fi
fi

# JSON cevabı klasik whois benzeri text'e indirgeyerek bas
echo "% RDAP HTTPS query (whois TCP/43 alternatifi) — mebkali-rdap-wrapper"
echo "% Source: $srv  Target: $DOMAIN"
echo

if command -v jq >/dev/null 2>&1; then
  echo "$RESULT" | jq -r '
    [
      ["Domain Name",        (.ldhName // .name // "-")],
      ["Handle",             (.handle // "-")],
      ["Status",             ((.status // []) | join(", ") )],
      ["Created",            ((.events // []) | map(select(.eventAction=="registration"))[0].eventDate // "-")],
      ["Updated",            ((.events // []) | map(select(.eventAction=="last changed"))[0].eventDate // "-")],
      ["Expires",            ((.events // []) | map(select(.eventAction=="expiration"))[0].eventDate // "-")],
      ["Nameservers",        ((.nameservers // []) | map(.ldhName) | join(", "))],
      ["Registrar",          ((.entities // []) | map(select((.roles // []) | index("registrar")))[0].vcardArray[1] | (map(select(.[0]=="fn"))[0][3] // "-"))]
    ] | .[] | "\(.[0]):\t\(.[1])"
  ' 2>/dev/null

  echo
  echo "% Tüm registrar/admin/teknik iletişim bilgileri:"
  echo "$RESULT" | jq -r '
    (.entities // [])[] |
    "  [\((.roles // []) | join(","))]  \(.vcardArray[1] | (map(select(.[0]=="fn"))[0][3] // "-"))"
  ' 2>/dev/null

  echo
  echo "% Ham RDAP JSON için: whois <domain> --json   (wrapper bayrağı, devre dışı; tam JSON için curl)"
else
  echo "$RESULT"
fi
WRAP
  chmod 0755 "$WRAPPER"
  ok "Wrapper yazıldı: $WRAPPER"
fi

# 4) Doğrulama
say "3/3 Wrapper doğrulama (whois example.com)..."
WHICH_WHOIS="$(command -v whois)"
if [[ "$WHICH_WHOIS" == "$WRAPPER" ]]; then
  ok "command -v whois → $WRAPPER (wrapper aktif)"
else
  warn "command -v whois → $WHICH_WHOIS  (PATH öncelik /usr/local/bin'de değil mi?)"
fi

# Çalıştırma testi (head pipe SIGPIPE'ı pipefail ile çakışmasın diye iki aşama)
TEST_FULL="$( "$WRAPPER" example.com 2>&1 || true )"
TEST_OUT="$(printf '%s\n' "$TEST_FULL" | head -n 12 || true)"
if echo "$TEST_OUT" | grep -q "Domain Name:"; then
  ok "RDAP wrapper çalışıyor:"
  echo "$TEST_OUT" | sed 's/^/    /'
else
  err "RDAP wrapper test başarısız:"
  echo "$TEST_OUT" | sed 's/^/    /'
  exit 1
fi

echo
hl "━━━ Diğer araçlar için ipuçları ━━━"
echo
echo "${YELLOW}theHarvester${NC} — Search engine bazı motorları MITM tarafından bozulduğu için"
echo "  JSON parse hatası verir. Engine'i değiştir veya birden fazla dene:"
echo "    theHarvester -d example.com -b bing       # bazen DDG yerine bing"
echo "    theHarvester -d example.com -b crtsh      # CT log'lardan, HTTPS"
echo "    theHarvester -d example.com -b otx        # AlienVault OTX, HTTPS"
echo "    theHarvester -d example.com -b hunter     # Hunter.io (HTTPS, API key gerekebilir)"
echo
echo "${YELLOW}dnsenum${NC} — AXFR (TCP/53) timeout normal davranış (auth servers reddeder ya"
echo "  MEB engeller). Diğer modlar HTTPS üzerinden çalışır:"
echo "    dnsenum --noreverse --threads 5 example.com   # AXFR atlar"
echo "    dnsrecon -d example.com -t std,brt            # alternatif HTTPS-tabanlı"
echo
echo "${YELLOW}nmap dış scan${NC} — outbound port-scan zaten MEB firewall'unda bloklu;"
echo "  iç ağ taraması (LAN) çalışmaya devam eder. -sT ile TCP connect kullan."
echo
echo "${YELLOW}Genel${NC} — HTTPS dışı protokoller (SMTP, IRC, NTP-direct, IMAP)"
echo "  bloklu. Bu araçların HTTPS-tabanlı modları/API'leri tercih edilmeli."
