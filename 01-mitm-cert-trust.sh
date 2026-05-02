#!/usr/bin/env bash
# 01-mitm-cert-trust.sh
# MEB MITM kök sertifikasını (fatihca) tüm trust depolarına idempotent olarak ekler.
# Çalıştırma: sudo bash 01-mitm-cert-trust.sh
#
# Yan dizinde MEB_SERTIFIKASI.crt bulunmalıdır. Opsiyonel: libnss3-tools*.deb
# (Firefox/Chromium NSS DB için certutil yoksa). Betik:
#   - /usr/local/share/ca-certificates/'a cert kopyalar, update-ca-certificates
#   - p11-kit anchor (best-effort, kritik değil)
#   - certutil yoksa libnss3-tools kurar (önce yan deb, sonra apt)
#   - Tüm Firefox profillerine cert ekler + enterprise_roots.enabled=true
#   - Chromium NSS DB (yoksa oluşturur) cert ekler
#   - /etc/profile.d/meb-ca.sh: SSL_CERT_FILE, REQUESTS_CA_BUNDLE, vb.
#   - /usr/local/lib/python3.X/dist-packages/meb_mitm_fix.{py,pth} (apt-upgrade-proof)
#   - curl/openssl/git/python doğrulama testleri

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

# nss_db_has_cert <db_dir> <expected_sha256_hex_lowercase_no_colons>
# DB'deki tüm cert'lerin parmakizini cıkarır, eşleşeni varsa 0 döner.
# Nickname-bağımsız: NSS aynı cert'i farklı nickname ile yeniden eklemez.
nss_db_has_cert() {
  local db="$1" want="$2" nick fpr
  while IFS= read -r nick; do
    [[ -z "$nick" ]] && continue
    fpr="$(sudo -u "$TARGET_USER" certutil -L -d "sql:$db" -n "$nick" -a 2>/dev/null \
           | openssl x509 -noout -fingerprint -sha256 2>/dev/null \
           | sed 's/^.*=//' | tr -d ':' | tr 'A-F' 'a-f')"
    [[ "$fpr" == "$want" ]] && return 0
  done < <(sudo -u "$TARGET_USER" certutil -L -d "sql:$db" 2>/dev/null \
           | awk 'NR>4 && NF>0 {
                    sub(/[ \t]+$/, "");
                    sub(/[ \t][ \t]+[A-Za-z,]+$/, "");
                    print
                  }')
  return 1
}

TARGET_USER="${SUDO_USER:-kali}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || { err "Hedef kullanıcı home yok: $TARGET_USER"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_SRC="$SCRIPT_DIR/MEB_SERTIFIKASI.crt"
CERT_NAME="MEB_SERTIFIKASI"
CERT_DST="/usr/local/share/ca-certificates/${CERT_NAME}.crt"
SYSTEM_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
ENV_FILE="/etc/profile.d/meb-ca.sh"
NICKNAME="MEB MITM Root (fatihca)"
EXPECTED_FPR="C4:F8:04:D0:93:BA:78:5D:EB:C6:9B:59:17:F2:99:FE:6E:A9:E8:AA:2E:66:83:E8:3F:4D:C9:CD:51:C0:8E:75"

# 0) Cert dosyası var mı, beklenen parmakizi mi?
say "Cert dosyası kontrolü..."
[[ -f "$CERT_SRC" ]] || { err "Cert bulunamadı: $CERT_SRC"; exit 1; }
ACTUAL_FPR="$(openssl x509 -in "$CERT_SRC" -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//')"
if [[ "$ACTUAL_FPR" == "$EXPECTED_FPR" ]]; then
  ok "Parmakizi eşleşti"
else
  warn "Parmakizi farklı (devam ediliyor):"
  printf "  beklenen: %s\n  gelen:    %s\n" "$EXPECTED_FPR" "$ACTUAL_FPR"
fi
FPR_LC="$(echo "$ACTUAL_FPR" | tr -d ':' | tr 'A-F' 'a-f')"

# 1) Sistem CA bundle (curl, wget, git, openssl, apt)
say "1/7 Sistem CA bundle..."
install -m 0644 -o root -g root "$CERT_SRC" "$CERT_DST"
update-ca-certificates >/dev/null
CERT_HASH="$(openssl x509 -in "$CERT_DST" -noout -hash)"
if [[ -e "/etc/ssl/certs/${CERT_HASH}.0" ]] && openssl verify -CAfile "$SYSTEM_BUNDLE" "$CERT_DST" >/dev/null 2>&1; then
  ok "Sistem bundle güncel (hash link: ${CERT_HASH}.0, openssl verify OK)"
else
  err "update-ca-certificates başarısız (hash link yok veya cert bundle'da değil)"
  exit 1
fi

# 2) p11-kit shared trust (best-effort; Debian/Kali'de yazılabilir konum
# konfigürasyonu olmayabilir — kritik değil, NSS DB ile zaten kapsanıyor)
say "2/7 p11-kit shared trust (best-effort)..."
if trust list --filter=ca-anchors 2>/dev/null | tr 'A-F' 'a-f' | tr -d ': ' | grep -q "$FPR_LC"; then
  ok "p11-kit'te zaten anchor edilmiş"
elif trust anchor "$CERT_DST" 2>/dev/null; then
  ok "p11-kit anchor eklendi"
else
  ok "Debian/Kali'de p11-kit yazılabilir konum sunmuyor — bu adım gereksiz (NSS DB ile zaten kapsanıyor)"
fi

# 3) certutil yoksa libnss3-tools kur (önce yan deb, sonra apt)
say "3/7 certutil (libnss3-tools)..."
if command -v certutil >/dev/null 2>&1; then
  ok "certutil zaten var"
else
  INSTALLED=0
  shopt -s nullglob
  LOCAL_DEBS=("$SCRIPT_DIR"/libnss3-tools*.deb)
  shopt -u nullglob
  if (( ${#LOCAL_DEBS[@]} > 0 )); then
    if dpkg -i "${LOCAL_DEBS[@]}" >/dev/null 2>&1; then
      ok "libnss3-tools yan dizindeki .deb'den kuruldu: $(basename "${LOCAL_DEBS[0]}")"
      INSTALLED=1
    else
      warn ".deb dpkg kurulumu başarısız (bağımlılıklar eksik olabilir)"
    fi
  fi
  if (( INSTALLED == 0 )) && apt-get install -y --no-install-recommends libnss3-tools >/dev/null 2>&1; then
    ok "libnss3-tools apt'tan kuruldu"
    INSTALLED=1
  fi
  if (( INSTALLED == 0 )); then
    warn "certutil kurulamadı - Firefox/Chromium adımları atlanacak"
  fi
fi

# 4) Firefox profilleri (NSS DB import + user.js enterprise_roots)
say "4/7 Firefox profilleri..."
if ! command -v certutil >/dev/null 2>&1; then
  warn "certutil yok, Firefox adımı atlanıyor"
else
  FFOX_PROFILES=()
  shopt -s nullglob
  for d in "$TARGET_HOME"/.mozilla/firefox/*.default* \
           "$TARGET_HOME"/snap/firefox/common/.mozilla/firefox/*.default* \
           "$TARGET_HOME"/.var/app/org.mozilla.firefox/.mozilla/firefox/*.default*; do
    [[ -d "$d" && -f "$d/cert9.db" ]] && FFOX_PROFILES+=("$d")
  done
  shopt -u nullglob

  if (( ${#FFOX_PROFILES[@]} == 0 )); then
    warn "Firefox profili yok — Firefox'u bir kez açıp kapatın, sonra betiği yeniden çalıştırın"
  else
    for prof in "${FFOX_PROFILES[@]}"; do
      if nss_db_has_cert "$prof" "$FPR_LC"; then
        ok "Firefox profili güncel: $prof"
      elif sudo -u "$TARGET_USER" certutil -A -n "$NICKNAME" -t "C,," -i "$CERT_DST" -d "sql:$prof" 2>/dev/null \
           && nss_db_has_cert "$prof" "$FPR_LC"; then
        ok "Firefox profiline eklendi: $prof"
      else
        warn "Eklenemedi (Firefox açık olabilir, kapatıp tekrar deneyin): $prof"
      fi
      USERJS="$prof/user.js"
      if ! grep -q "enterprise_roots.enabled" "$USERJS" 2>/dev/null; then
        echo 'user_pref("security.enterprise_roots.enabled", true);' >> "$USERJS"
        chown "$TARGET_USER:$TARGET_USER" "$USERJS"
        ok "user.js: enterprise_roots etkinleştirildi"
      fi
    done
  fi
fi

# 5) Chromium / Chrome NSS DB
say "5/7 Chromium/Chrome NSS DB..."
NSSDB="$TARGET_HOME/.pki/nssdb"
if ! command -v certutil >/dev/null 2>&1; then
  warn "certutil yok, Chromium adımı atlanıyor"
else
  if [[ ! -f "$NSSDB/cert9.db" ]]; then
    sudo -u "$TARGET_USER" mkdir -p "$NSSDB"
    if sudo -u "$TARGET_USER" certutil -N --empty-password -d "sql:$NSSDB" >/dev/null 2>&1; then
      ok "Chromium NSS DB oluşturuldu (boş şifre ile): $NSSDB"
    else
      warn "Chromium NSS DB oluşturulamadı"
    fi
  fi
  if [[ -f "$NSSDB/cert9.db" ]]; then
    if nss_db_has_cert "$NSSDB" "$FPR_LC"; then
      ok "Chromium NSS DB güncel"
    elif sudo -u "$TARGET_USER" certutil -A -n "$NICKNAME" -t "C,," -i "$CERT_DST" -d "sql:$NSSDB" 2>/dev/null \
         && nss_db_has_cert "$NSSDB" "$FPR_LC"; then
      ok "Chromium NSS DB'sine eklendi"
    else
      warn "Chromium NSS DB ekleme başarısız"
    fi
  fi
fi

# 6) Sistem geneli env vars
say "6/7 /etc/profile.d/meb-ca.sh (sistem geneli env vars)..."
cat > "$ENV_FILE" <<'EOF'
# MEB MITM CA - tüm araçlar sistem CA bundle'ını kullansın
# 01-mitm-cert-trust.sh tarafından oluşturuldu
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export PIP_CERT=/etc/ssl/certs/ca-certificates.crt
export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
EOF
chmod 0644 "$ENV_FILE"
ok "Env yazıldı: $ENV_FILE"

# 7) Python: VERIFY_X509_STRICT yaması (apt-upgrade-proof)
# Yaklaşım: /usr/local/lib/python3.X/dist-packages/ altına bir modül + .pth
# dosyası yerleştirilir. .pth dosyası Python'un site init mekanizması ile
# her Python başlangıcında otomatik yüklenir. /usr/local/... apt tarafından
# dokunulmaz, böylece python3 paket güncellemeleri yamamızı silmez.
say "7/7 Python sitecustomize (apt-upgrade-proof) yamayı..."

# 7a) Önceki yaklaşımı temizle (eski /etc/python3*/sitecustomize.py marker'ları)
shopt -s nullglob
for OLDSITE in /etc/python3*/sitecustomize.py; do
  if grep -qF "# >>> meb-mitm-fix begin" "$OLDSITE" 2>/dev/null; then
    sed -i '/# >>> meb-mitm-fix begin/,/# <<< meb-mitm-fix end/d' "$OLDSITE"
    ok "Eski yama temizlendi: $OLDSITE"
  fi
done
shopt -u nullglob

# 7b) Python sürümlerini keşfet
PY_VERS=()
shopt -s nullglob
for d in /usr/lib/python3.*; do
  [[ -d "$d" ]] || continue
  base="$(basename "$d")"   # python3.13
  ver="${base#python}"      # 3.13
  if [[ "$ver" =~ ^3\.[0-9]+$ ]]; then
    PY_VERS+=("$ver")
  fi
done
shopt -u nullglob
(( ${#PY_VERS[@]} > 0 )) || { warn "Hiç Python 3.X bulunamadı"; PY_VERS=(); }

# 7c) Modül içeriği
read -r -d '' MEB_FIX_PY <<'PYEOF' || true
"""MEB MITM cert chain'inde Authority Key Identifier eksik; Python 3.13'un
default VERIFY_X509_STRICT bayragi bunu reddediyor. Bu modul ssl ve urllib3'un
context create fonksiyonlarini yamayarak yalnizca ekstra strict bayragi siler.
Normal sertifika zincir dogrulamasi korunur.

01-mitm-cert-trust.sh tarafindan /usr/local/lib/python3.X/dist-packages/
altina yazilir; ayni dizindeki meb_mitm_fix.pth ('import meb_mitm_fix') Python
her baslangicinda bu modulu yukler. /usr/local/... apt tarafindan dokunulmaz,
python3 paket yukseltmeleri yamayi silmez.

urllib3 yamasi neden deferred? .pth /usr/local/.../dist-packages/'da islerken
/usr/lib/python3/dist-packages/ (urllib3'un yeri) henuz sys.path'e eklenmis
olmayabilir. Bu nedenle urllib3 yamasi __import__ hook'u ile urllib3 ilk
yuklendiginde uygulanir.
"""

try:
    import ssl as _ssl
    _orig_cdc = _ssl.create_default_context

    def _patched_cdc(*args, **kwargs):
        ctx = _orig_cdc(*args, **kwargs)
        try:
            ctx.verify_flags &= ~_ssl.VERIFY_X509_STRICT
        except Exception:
            pass
        return ctx

    _ssl.create_default_context = _patched_cdc
    _ssl._create_default_https_context = _patched_cdc

    def _patch_urllib3_now():
        """urllib3 sys.modules'taysa context create fonksiyonlarini yama.
        Tum import-time kopyalari (urllib3.connection.create_urllib3_context vb)
        ayri ayri rebind edilir."""
        import sys as _sys
        u3 = _sys.modules.get("urllib3.util.ssl_")
        u3conn = _sys.modules.get("urllib3.connection")
        if u3 is None or u3conn is None:
            return False
        u3util = _sys.modules.get("urllib3.util")
        u3root = _sys.modules.get("urllib3")
        orig = u3.create_urllib3_context
        if getattr(orig, "_meb_patched", False):
            return True

        def _patched_u3(*args, **kwargs):
            ctx = orig(*args, **kwargs)
            try:
                ctx.verify_flags &= ~_ssl.VERIFY_X509_STRICT
            except Exception:
                pass
            return ctx

        _patched_u3._meb_patched = True
        for _mod in (u3, u3conn, u3util, u3root):
            if _mod is not None and hasattr(_mod, "create_urllib3_context"):
                _mod.create_urllib3_context = _patched_u3
        return True

    if not _patch_urllib3_now():
        # urllib3 henuz yuklenmemis — __import__ hook'u ile defer et
        import builtins as _builtins
        _orig_import = _builtins.__import__
        _meb_done = [False]

        def _meb_import(name, *args, **kwargs):
            mod = _orig_import(name, *args, **kwargs)
            if not _meb_done[0]:
                try:
                    if _patch_urllib3_now():
                        _meb_done[0] = True
                except Exception:
                    pass
            return mod

        _builtins.__import__ = _meb_import
except Exception:
    pass
PYEOF

# 7d) Yamayı iki ayrı konuma yerleştir (defense-in-depth):
#  (a) /usr/lib/python3/dist-packages/ — versiyonsuz, TÜM Python 3.X'lerin
#      (mevcut + ileride kurulacak) sys.path'inde otomatik bulunur. Bu sayede
#      python3 minor upgrade (3.13 -> 3.14) sonrası yeniden çalıştırma gerekmez.
#  (b) /usr/local/lib/python3.X/dist-packages/ — keşfedilen her sürüm için.
#      apt asla /usr/local'a dokunmaz; (a) bir nedenle silinirse buradan devam.
DEPLOY_PY_PATCH() {
  local dest="$1"
  install -d -m 0755 "$dest"
  printf '%s' "$MEB_FIX_PY" > "$dest/meb_mitm_fix.py"
  chmod 0644 "$dest/meb_mitm_fix.py"
  echo 'import meb_mitm_fix' > "$dest/meb_mitm_fix.pth"
  chmod 0644 "$dest/meb_mitm_fix.pth"
  ok "Yama yerleştirildi: $dest/meb_mitm_fix.{py,pth}"
}

# (a) Versiyonsuz primary konum
DEPLOY_PY_PATCH /usr/lib/python3/dist-packages

# (b) Her keşfedilen Python sürümü için /usr/local altına da yaz
for ver in "${PY_VERS[@]}"; do
  DEPLOY_PY_PATCH "/usr/local/lib/python${ver}/dist-packages"
done

# 8) Doğrulama testleri (yeni shell ortamında)
say "Doğrulama testleri..."
FAIL=0

if curl -sfI --max-time 10 "https://www.google.com" -o /dev/null; then
  ok "curl  https://www.google.com  OK"
else
  err "curl başarısız"; FAIL=1
fi

if echo | openssl s_client -connect www.google.com:443 -servername www.google.com \
     -CAfile "$SYSTEM_BUNDLE" -verify_return_error </dev/null >/dev/null 2>&1; then
  ok "openssl verify OK"
else
  err "openssl verify başarısız"; FAIL=1
fi

if git ls-remote https://github.com/torvalds/linux.git HEAD >/dev/null 2>&1; then
  ok "git https github  OK"
else
  err "git https başarısız"; FAIL=1
fi

# Python testleri: target_user olarak çalıştır, env'i source et, .pth otomatik yüklenir
PY_TESTS=$(sudo -u "$TARGET_USER" bash -c '
  source /etc/profile.d/meb-ca.sh
  python3 - <<PY 2>&1
import sys
def t(name, fn):
    try:
        fn(); print(f"OK {name}")
    except Exception as e:
        print(f"FAIL {name}: {type(e).__name__}: {str(e)[:120]}")
def urllib_test():
    import urllib.request
    urllib.request.urlopen("https://www.google.com", timeout=10).read(64)
def requests_test():
    import requests
    r = requests.get("https://www.google.com", timeout=10)
    assert r.status_code == 200
def pth_loaded():
    import meb_mitm_fix  # yuklenmis olmali
t("urllib.request", urllib_test)
t("requests", requests_test)
t("meb_mitm_fix yüklendi", pth_loaded)
PY
') || true

while IFS= read -r line; do
  case "$line" in
    "OK "*)   ok "python ${line#OK }"   ;;
    "FAIL "*) err "python ${line#FAIL }"; FAIL=1 ;;
    *)        [[ -n "$line" ]] && warn "python: $line" ;;
  esac
done <<< "$PY_TESTS"

# Firefox profilinde cert dogrulama
if command -v certutil >/dev/null 2>&1; then
  shopt -s nullglob
  ANY_FF=0; FF_OK=0
  for prof in "$TARGET_HOME"/.mozilla/firefox/*.default* \
              "$TARGET_HOME"/snap/firefox/common/.mozilla/firefox/*.default* \
              "$TARGET_HOME"/.var/app/org.mozilla.firefox/.mozilla/firefox/*.default*; do
    [[ -f "$prof/cert9.db" ]] || continue
    ANY_FF=1
    nss_db_has_cert "$prof" "$FPR_LC" && FF_OK=1
  done
  shopt -u nullglob
  if (( ANY_FF == 0 )); then
    warn "Firefox profili yok (atlandı)"
  elif (( FF_OK == 1 )); then
    ok "Firefox NSS DB'sinde MEB cert var"
  else
    err "Firefox NSS DB'sinde MEB cert yok"; FAIL=1
  fi

  # Chromium da kontrol et
  if [[ -f "$NSSDB/cert9.db" ]]; then
    if nss_db_has_cert "$NSSDB" "$FPR_LC"; then
      ok "Chromium NSS DB'sinde MEB cert var"
    else
      err "Chromium NSS DB'sinde MEB cert yok"; FAIL=1
    fi
  fi
fi

echo
if [[ $FAIL -ne 0 ]]; then
  err "Bazı doğrulama testleri başarısız"
  exit 1
fi
ok "Tüm trust depoları yapılandırıldı."
warn "Firefox/Chromium açıksa cert'i görmek için yeniden başlatın."
warn "Mevcut shell'lerde env: 'source /etc/profile.d/meb-ca.sh'"
