#!/usr/bin/env bash
# 12-etik-banner.sh
# Yasal/etik çerçeve — Bilişim Teknolojileri Alanı müfredatının gereği.
#   1. Masaüstü filigranı (conky): kimlik (kimden) + etik uyarısı (her zaman görünür)
#   2. ~/Desktop/ETIK-CERCEVE.pdf — 5651, KVKK, TCK 243 özet
#
# Çalıştırma: sudo bash 12-etik-banner.sh
# Geri alma: sudo bash 12-etik-banner.sh --revert

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

ETIK_DIR="/usr/share/mebkali"
ETIK_MD="$ETIK_DIR/etik-cerceve.md"
ETIK_HTML="$ETIK_DIR/ETIK-CERCEVE.html"
ETIK_PDF="$ETIK_DIR/ETIK-CERCEVE.pdf"
CONKY_RC="/etc/mebkali/etik.conkyrc"
CONKY_AUTOSTART="/etc/xdg/autostart/mebkali-conky.desktop"
DESKTOP_PDF_LINK="$TARGET_HOME/Desktop/ETIK-CERCEVE.pdf"
DESKTOP_HTML_LINK="$TARGET_HOME/Desktop/ETIK-CERCEVE.html"

# Apt timeout + ilerleme göstergesi — donmuş gibi durmasın
APT_OPTS=(
  -o Acquire::http::Timeout=15
  -o Acquire::https::Timeout=15
  -o Acquire::Retries=1
  -o DPkg::Lock::Timeout=30
)
apt_install_progress() {
  local pkg="$1" tmo="${2:-90}" logf
  logf="$(mktemp)"
  printf "  ${BLUE}[*]${NC} %s kuruluyor (en fazla %ds)...\n" "$pkg" "$tmo"
  ( env DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_OPTS[@]}" --no-install-recommends "$pkg" >"$logf" 2>&1 ) &
  local pid=$! t=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 3; t=$((t+3))
    printf "  ${BLUE}[*]${NC} %s ... %ds geçti%s\n" "$pkg" "$t" \
      "$(tail -1 "$logf" 2>/dev/null | head -c 40 | sed 's/[^[:print:]]//g; s/^/ — /')"
    if (( t >= tmo )); then
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
      printf "  ${YELLOW}[!]${NC} %s kurulumu %ds zaman aşımına uğradı\n" "$pkg" "$tmo"
      rm -f "$logf"; return 124
    fi
  done
  wait "$pid"; local rc=$?
  if [[ $rc -eq 0 ]]; then
    printf "  ${GREEN}[+]${NC} %s kuruldu (%ds)\n" "$pkg" "$t"
  else
    printf "  ${YELLOW}[!]${NC} %s kurulamadı (rc=%d)\n" "$pkg" "$rc"
    tail -3 "$logf" 2>/dev/null | sed 's/^/      ┄ /'
  fi
  rm -f "$logf"; return $rc
}

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma..."
  pkill -u "$TARGET_USER" -x conky 2>/dev/null || true
  rm -f "$CONKY_RC" "$CONKY_AUTOSTART"
  rm -rf "$ETIK_DIR"
  rm -f "$DESKTOP_PDF_LINK" "$DESKTOP_HTML_LINK"
  ok "Etik banner + conky kaldırıldı"
  exit 0
fi

mkdir -p "$ETIK_DIR" /etc/mebkali

# 1) Etik metni (markdown kaynak)
say "1/5 Etik metni: $ETIK_MD"
cat > "$ETIK_MD" <<'EOF'
% Etik ve Yasal Çerçeve
% MEBKALI Sınıf Ortamı
% Bilişim Teknolojileri Alanı — Siber Güvenlik Dalı

# Etik ve Yasal Çerçeve

Bu makine **yetkili bir eğitim ortamı**dır. Siber güvenlik araçları
yalnızca **sahibi olduğunuz**, **yazılı izin aldığınız** veya
**öğretmenin tahsis ettiği** sistemler üzerinde kullanılabilir.

## TCK 243 — Bilişim sistemine girme

> "Bir bilişim sisteminin bütününe veya bir kısmına, hukuka aykırı
> olarak giren veya orada kalmaya devam eden kimseye **bir yıla
> kadar hapis veya adli para cezası** verilir."

Sınıf laboratuvarı dışında bir sisteme — okul, ev, kafe Wi-Fi'sındaki
makinelere — *test maksatlı bile olsa* erişim girişimi suçtur.

## TCK 244 — Sistemi engelleme, bozma, veri yok etme

Bir bilişim sistemindeki verileri **bozmak, silmek, değiştirmek**;
sistemin işleyişini **engellemek**: **6 aydan 3 yıla kadar hapis**.
Bu suç bir kazanç sağlamak için işlenmişse ceza yarı oranında artar.

## TCK 245 — Banka veya kredi kartının kötüye kullanılması

Başkasının banka/kredi kartını kullanarak haksız menfaat sağlamak:
**3 yıldan 6 yıla kadar hapis ve 5000 güne kadar adli para cezası**.

## 5651 Sayılı Kanun — İnternet ortamında düzenleme

İnternet üzerinden işlenen suçlarda **erişim sağlayıcı** ve
**içerik sağlayıcı**nın yükümlülükleri. Bu makine MEB ağına
bağlandığında trafik **MEB sertifikasıyla** denetlenir; bankacılık
veya kişisel hesap girişi yapmayın.

## KVKK — Kişisel Verilerin Korunması Kanunu (6698)

Başkasına ait kişisel veriyi **hukuka aykırı olarak elde etmek,
yaymak veya işlemek**: **1 yıldan 4 yıla kadar hapis** (KVKK md. 17,
TCK md. 135-140).

Sınıfta yapılan testlerde **gerçek kişi verisi** ile çalışmayın;
sadece bu VM içindeki yerel zafiyetli laboratuvarı (`mebkali-lab`)
ve öğretmenin onayladığı hedefleri kullanın.

## Yetkili Test İlkeleri (Bilişim Etiği)

1. **Yazılı izin** — her test için açık yetki belgesi.
2. **Kapsam** — sadece izin verilen sistemler, izin verilen yöntemler.
3. **Zarar vermeme** — veri silme, hizmet kesintisi yok.
4. **Gizlilik** — bulduğun zafiyet/veriyi paylaşma, yalnızca raporla.
5. **Kayıt** — yapılan her işlemi belgele (öğrenci defteri).

## Bu VM'i Doğru Kullanma

- Sınıf hedefi: `mebkali-lab basla` → http://127.0.0.1:8080/
- Dış internet hedefi yok — hatta dış internet bu derste değil.
- Soru/şüphe → önce **öğretmene danış**.

---

*Bu belge MTAL Bilişim Teknolojileri Alanı — Siber Güvenlik
Temelleri dersi için MEBKALI sınıf VM'iyle birlikte gelir.*
EOF
chmod 0644 "$ETIK_MD"
ok "Etik metni yazıldı"

# 2) HTML üret (her zaman) — tarayıcıda da açılabilir
say "2/5 HTML üretimi: $ETIK_HTML"
cat > "$ETIK_HTML" <<'HTML'
<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<title>Etik ve Yasal Çerçeve — MEBKALI</title>
<style>
  body { font-family: 'DejaVu Sans', system-ui, sans-serif; max-width: 760px;
         margin: 40px auto; padding: 0 24px; color: #1a1a1a; line-height: 1.55; }
  h1 { color: #b3261e; border-bottom: 3px solid #b3261e; padding-bottom: 8px; }
  h2 { color: #1c3d5a; margin-top: 28px; }
  blockquote { background: #fff3cd; border-left: 4px solid #b8860b;
               padding: 12px 16px; margin: 12px 0; }
  ol li { margin-bottom: 6px; }
  hr { border: none; border-top: 1px solid #ccc; margin: 28px 0; }
  .footer { font-size: 0.85em; color: #666; font-style: italic; }
  .badge { display: inline-block; background: #b3261e; color: white;
           padding: 2px 8px; border-radius: 3px; font-size: 0.85em; }
</style>
</head>
<body>
<h1>⚖️ Etik ve Yasal Çerçeve</h1>
<p><span class="badge">MEBKALI</span> &nbsp; <strong>Sınıf VM'i — Bilişim Teknolojileri Alanı / Siber Güvenlik Dalı</strong></p>

<p>Bu makine <strong>yetkili bir eğitim ortamı</strong>dır. Siber güvenlik araçları
yalnızca <strong>sahibi olduğunuz</strong>, <strong>yazılı izin aldığınız</strong> veya
<strong>öğretmenin tahsis ettiği</strong> sistemler üzerinde kullanılabilir.</p>

<h2>TCK 243 — Bilişim sistemine girme</h2>
<blockquote>"Bir bilişim sisteminin bütününe veya bir kısmına, hukuka aykırı
olarak giren veya orada kalmaya devam eden kimseye <strong>bir yıla kadar
hapis veya adli para cezası</strong> verilir."</blockquote>
<p>Sınıf laboratuvarı dışında bir sisteme — okul, ev, kafe Wi-Fi'sındaki
makinelere — <em>test maksatlı bile olsa</em> erişim girişimi suçtur.</p>

<h2>TCK 244 — Sistemi engelleme, bozma, veri yok etme</h2>
<p>Bir bilişim sistemindeki verileri <strong>bozmak, silmek, değiştirmek</strong>;
sistemin işleyişini <strong>engellemek</strong>: <strong>6 aydan 3 yıla kadar hapis</strong>.
Bu suç bir kazanç sağlamak için işlenmişse ceza yarı oranında artar.</p>

<h2>TCK 245 — Banka veya kredi kartının kötüye kullanılması</h2>
<p>Başkasının banka/kredi kartını kullanarak haksız menfaat sağlamak:
<strong>3 yıldan 6 yıla kadar hapis ve 5000 güne kadar adli para cezası</strong>.</p>

<h2>5651 Sayılı Kanun — İnternet ortamında düzenleme</h2>
<p>İnternet üzerinden işlenen suçlarda erişim sağlayıcı ve içerik
sağlayıcının yükümlülükleri. Bu makine MEB ağına bağlandığında trafik
<strong>MEB sertifikasıyla denetlenir</strong>; bankacılık veya kişisel hesap
girişi yapmayın.</p>

<h2>KVKK — Kişisel Verilerin Korunması Kanunu (6698)</h2>
<p>Başkasına ait kişisel veriyi hukuka aykırı olarak elde etmek, yaymak
veya işlemek: <strong>1 yıldan 4 yıla kadar hapis</strong> (KVKK md. 17,
TCK md. 135-140). Sınıfta yapılan testlerde <strong>gerçek kişi verisi</strong>
ile çalışmayın; sadece bu VM içindeki yerel zafiyetli laboratuvarı
(<code>mebkali-lab</code>) kullanın.</p>

<h2>Yetkili Test İlkeleri</h2>
<ol>
  <li><strong>Yazılı izin</strong> — her test için açık yetki belgesi.</li>
  <li><strong>Kapsam</strong> — sadece izin verilen sistemler ve yöntemler.</li>
  <li><strong>Zarar vermeme</strong> — veri silme, hizmet kesintisi yok.</li>
  <li><strong>Gizlilik</strong> — bulduğun zafiyet/veriyi paylaşma, yalnızca raporla.</li>
  <li><strong>Kayıt</strong> — yapılan her işlemi belgele (öğrenci defteri).</li>
</ol>

<h2>Bu VM'i doğru kullanma</h2>
<ul>
  <li>Sınıf hedefi: <code>mebkali-lab basla</code> → <a href="http://127.0.0.1:8080/">http://127.0.0.1:8080/</a></li>
  <li>Dış internet hedefi <strong>yok</strong>.</li>
  <li>Soru/şüphe → önce <strong>öğretmene danış</strong>.</li>
</ul>

<hr>
<p class="footer">MTAL Bilişim Teknolojileri Alanı — Siber Güvenlik Temelleri dersi için
MEBKALI sınıf VM'iyle birlikte gelir.</p>
</body>
</html>
HTML
chmod 0644 "$ETIK_HTML"
ok "HTML üretildi"

# 3) PDF üretimi — birkaç backend dene, başarısızsa HTML'le yetin
say "3/5 PDF üretimi..."
PDF_OK=0

# Önce wkhtmltopdf (en hızlı + güzel UTF-8)
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
  apt_install_progress wkhtmltopdf 90 || true
fi
if command -v wkhtmltopdf >/dev/null 2>&1; then
  if wkhtmltopdf --quiet --enable-local-file-access \
       --encoding utf-8 --margin-top 18mm --margin-bottom 18mm \
       "$ETIK_HTML" "$ETIK_PDF" 2>/dev/null; then
    PDF_OK=1
    ok "PDF üretildi (wkhtmltopdf)"
  fi
fi

# Fallback: pandoc + weasyprint
if (( PDF_OK == 0 )); then
  if ! command -v pandoc >/dev/null 2>&1; then
    apt_install_progress pandoc 90 || true
  fi
  if ! command -v weasyprint >/dev/null 2>&1; then
    apt_install_progress weasyprint 90 || true
  fi
  if command -v pandoc >/dev/null 2>&1 && command -v weasyprint >/dev/null 2>&1; then
    if pandoc "$ETIK_MD" -o "$ETIK_PDF" --pdf-engine=weasyprint 2>/dev/null; then
      PDF_OK=1
      ok "PDF üretildi (pandoc + weasyprint)"
    fi
  fi
fi

# Fallback: paps + ps2pdf (Unicode-safe text-only)
if (( PDF_OK == 0 )); then
  if ! command -v paps >/dev/null 2>&1; then
    apt_install_progress paps 60 || true
  fi
  if command -v paps >/dev/null 2>&1 && command -v ps2pdf >/dev/null 2>&1; then
    # Markdown'ı düz metne çevir (basit sed)
    TMPTXT="$(mktemp)"
    sed -E 's/^#+ //g; s/[*_`>]//g' "$ETIK_MD" > "$TMPTXT"
    if paps --paper=A4 --landscape=false "$TMPTXT" 2>/dev/null | ps2pdf - "$ETIK_PDF" 2>/dev/null; then
      PDF_OK=1
      ok "PDF üretildi (paps + ps2pdf — sade biçim)"
    fi
    rm -f "$TMPTXT"
  fi
fi

if (( PDF_OK == 0 )); then
  warn "PDF üretilemedi — HTML sürümü masaüstüne konacak"
fi
chmod 0644 "$ETIK_PDF" 2>/dev/null || true

# 4) Masaüstü kısayolları
say "4/5 Masaüstü kısayolları..."
if [[ -d "$TARGET_HOME/Desktop" ]]; then
  if (( PDF_OK )); then
    ln -sf "$ETIK_PDF" "$DESKTOP_PDF_LINK"
    chown -h "$TARGET_USER:$TARGET_USER" "$DESKTOP_PDF_LINK"
    ok "Masaüstü kısayolu: $DESKTOP_PDF_LINK"
  fi
  ln -sf "$ETIK_HTML" "$DESKTOP_HTML_LINK"
  chown -h "$TARGET_USER:$TARGET_USER" "$DESKTOP_HTML_LINK"
  ok "Masaüstü kısayolu: $DESKTOP_HTML_LINK"
fi

# 5) Conky filigranı
say "5/5 Conky filigranı (sürekli görünür)..."
if ! command -v conky >/dev/null 2>&1; then
  apt_install_progress conky-std 60 || true
fi
if ! command -v conky >/dev/null 2>&1; then
  warn "conky kurulamadı — filigran atlanıyor (PDF/HTML hâlâ var)"
else
  # Conky'nin ${execi} bloğu içindeki $VAR conky tarafından genişletilmek istenir;
  # bunu önlemek için harici bir shell script kullanılır.
  CONKY_HELPER="/usr/share/mebkali/conky-kimlik.sh"
  cat > "$CONKY_HELPER" <<'HELPER'
#!/bin/sh
# Conky'ye kimlik blok metni ver
if [ -r /etc/mebkali/kimlik.conf ]; then
  . /etc/mebkali/kimlik.conf
  printf "Öğrenci: %s\n" "${OGRENCI:-?}"
  printf "Sınıf:   %s\n" "${SINIF:-?}"
  printf "Dönem:   %s\n" "${DONEM:-?}"
else
  printf "Kimlik kayıtlı değil\n"
  printf "Komut: mebkali-kimlik\n"
fi
HELPER
  chmod 0755 "$CONKY_HELPER"

  cat > "$CONKY_RC" <<'CONKY'
-- /etc/mebkali/etik.conkyrc
-- Sınıf VM'i filigranı: kimlik + etik uyarısı.
-- mebkali tarafından üretildi (12-etik-banner.sh)

conky.config = {
  alignment = 'top_right',
  background = true,
  border_width = 0,
  default_color = 'white',
  default_outline_color = 'black',
  default_shade_color = 'black',
  draw_borders = false,
  draw_graph_borders = false,
  draw_outline = false,
  draw_shades = true,
  use_xft = true,
  font = 'DejaVu Sans:size=9',
  gap_x = 18,
  gap_y = 18,
  minimum_height = 5,
  minimum_width = 280,
  net_avg_samples = 2,
  no_buffers = true,
  out_to_console = false,
  out_to_stderr = false,
  extra_newline = false,
  own_window = true,
  own_window_class = 'Conky',
  own_window_type = 'desktop',
  own_window_transparent = true,
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  own_window_argb_visual = true,
  own_window_argb_value = 110,
  stippled_borders = 0,
  update_interval = 5.0,
  uppercase = false,
  use_spacer = 'none',
  show_graph_scale = false,
  show_graph_range = false,
  override_utf8_locale = true,
}

conky.text = [[
${color #ffd54f}${font DejaVu Sans:bold:size=10}MEBKALI — Sınıf VM${font}${color}
${execi 60 /usr/share/mebkali/conky-kimlik.sh}
${color #888}─────────────────────────${color}
${color #ff8a65}⚖${color} ${color #ffcdd2}Yetkili eğitim ortamı${color}
${color #888}TCK 243 · 244 · KVKK · 5651${color}
${color #888}Yetkisiz erişim suçtur${color}
]]
CONKY
  chmod 0644 "$CONKY_RC"
  ok "Conky yapılandırması yazıldı"

  # Autostart .desktop
  cat > "$CONKY_AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=MEBKALI Etik Filigranı
Name[tr]=MEBKALI Etik Filigranı
Comment=Masaüstünde sınıf kimliği + etik uyarısını sürekli gösterir
Exec=sh -c "sleep 5 && conky -c $CONKY_RC -d"
OnlyShowIn=XFCE;GNOME;MATE;LXDE;LXQt;
Terminal=false
NoDisplay=false
X-GNOME-Autostart-Delay=5
EOF
  chmod 0644 "$CONKY_AUTOSTART"
  ok "Autostart: $CONKY_AUTOSTART"

  # Halihazırda XFCE oturumu açıksa hemen başlat
  if pgrep -u "$TARGET_USER" -x xfce4-session >/dev/null 2>&1; then
    pkill -u "$TARGET_USER" -x conky 2>/dev/null || true
    sudo -u "$TARGET_USER" \
      DISPLAY=:0 XAUTHORITY="$TARGET_HOME/.Xauthority" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
      nohup conky -c "$CONKY_RC" -d >/dev/null 2>&1 &
    ok "Conky filigranı şu anki oturuma da yansıdı"
  fi
fi

echo
ok "Etik banner kuruldu."
[[ $PDF_OK -eq 1 ]] && echo "  PDF : $ETIK_PDF (masaüstünde de kısayol)"
echo "  HTML: $ETIK_HTML (masaüstünde de kısayol)"
echo "  Filigran: bir sonraki oturumdan itibaren her zaman görünür"
