#!/usr/bin/env bash
# 08-shell-welcome.sh
# Bash/Zsh için Türkçe alias seti.
# Sınıfta öğrenci Türkçe komut alternatiflerini kullanabilsin.
#
# Çalıştırma: sudo bash 08-shell-welcome.sh
# Geri alma: sudo bash 08-shell-welcome.sh --revert

set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; NC=$'\033[0m'
say()  { printf "%s[*]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[-]%s %s\n" "$RED"    "$NC" "$*" >&2; }

[[ $EUID -eq 0 ]] || { err "Bu betik root yetkisi gerektirir. Çalıştırma: sudo bash $0"; exit 1; }

MODE="${1:-apply}"

PROFILED="/etc/profile.d/mebkali-shell.sh"
ALIASES="/etc/mebkali/aliases.sh"
# Eski welcome.sh — varsa silinmesi gereken (artık üretilmiyor)
OLD_WELCOME="/etc/mebkali/welcome.sh"
BASHRC="/etc/bash.bashrc"
ZSHRC="/etc/zsh/zshrc"
SIGN="# mebkali-shell-welcome"

if [[ "$MODE" == "--revert" ]]; then
  say "Geri alma..."
  rm -f "$PROFILED" "$ALIASES" "$OLD_WELCOME"
  for f in "$BASHRC" "$ZSHRC"; do
    [[ -f "$f" ]] || continue
    sed -i "/$SIGN/,/$SIGN end/d" "$f"
  done
  ok "Alias seti kaldırıldı"
  exit 0
fi

mkdir -p /etc/mebkali

# 1) Alias dosyası — bash ve zsh ortak
say "1/2 Türkçe alias dosyası: $ALIASES"
cat > "$ALIASES" <<'EOF'
# /etc/mebkali/aliases.sh
# Türkçe komut alternatifleri — bash ve zsh ortak.
# mebkali tarafından üretildi (08-shell-welcome.sh)

# Dosya/dizin
alias liste='ls -lh --color=auto'
alias listele='ls -lah --color=auto'
alias klasor='ls -d */ 2>/dev/null'
alias yeni='mkdir -p'
alias sil='rm -i'
alias kopyala='cp -i'
alias tasi='mv -i'
alias bul='find . -iname'
alias ara='grep -rni --color=auto'
alias nerdeyim='pwd'
alias gec='cd'
alias temizle='clear'
alias agacgoster='tree -L 2'
alias agla='tail -f'

# Sistem
alias guncelle='sudo apt update && sudo apt upgrade -y'
alias kur='sudo apt install'
alias kaldir='sudo apt remove'
alias paketara='apt search'
alias bellekdurum='free -h'
alias diskdurum='df -h --output=source,size,used,avail,pcent,target | grep -v tmpfs'
alias islemler='ps aux --sort=-%mem | head -15'
alias ozet='history | tail -20'

# Ağ
alias ipadres='ip -br -c addr'
alias yolizle='traceroute'
alias dinle='sudo tcpdump -i any'
alias portlar='ss -tulnp'
alias bagli='ss -tnp'

# Siber Güvenlik (MTAL müfredatı)
alias tara='nmap -sV -Pn'
alias hizliTara='nmap -T4 -F'
alias derinTara='nmap -sV -sC -A -Pn'
alias aramotor='searchsploit'
alias kabuk='msfconsole -q'
alias yetkial='sudo -i'
alias zafiyetli='mebkali-lab basla && xdg-open http://127.0.0.1:8080/ >/dev/null 2>&1 &'

# Türkçe karakter dostu less + grep
# (yardim komutu 09-manpages-tr.sh tarafından /usr/local/bin/yardim olarak üretilir)
alias az='less -R'
alias filtre='grep --color=auto'
EOF
chmod 0644 "$ALIASES"
ok "alias dosyası yazıldı (29 alias)"

# 1a) Eski welcome.sh varsa temizle (önceki sürüm yüklediyse)
if [[ -f "$OLD_WELCOME" ]]; then
  rm -f "$OLD_WELCOME"
  ok "Eski welcome.sh kaldırıldı (artık banner gösterilmiyor)"
fi

# 2) profile.d girişi — login bash ve zsh otomatik source eder (sadece alias)
say "2/2 Sistem geneli source noktası: $PROFILED"
cat > "$PROFILED" <<EOF
$SIGN
# /etc/profile.d/mebkali-shell.sh — login bash & zsh için Türkçe alias
[[ -r $ALIASES ]] && . $ALIASES
EOF
chmod 0644 "$PROFILED"
ok "$PROFILED yazıldı"

# bash interactive non-login için /etc/bash.bashrc — alias bloğunu güncel tut
ensure_source_block() {
  local rcfile="$1"
  [[ -f "$rcfile" ]] || return 0
  # Eski blok varsa (welcome.sh source eden) sil; yenisini ekle
  if grep -q "$SIGN" "$rcfile" 2>/dev/null; then
    sed -i "/$SIGN/,/$SIGN end/d" "$rcfile"
  fi
  cat >> "$rcfile" <<EOF

$SIGN
# mebkali Türkçe alias seti
[[ -r $ALIASES ]] && . $ALIASES
$SIGN end
EOF
  ok "$rcfile içinde alias source bloğu güncel"
}

ensure_source_block "$BASHRC"
[[ -f "$ZSHRC" ]] && ensure_source_block "$ZSHRC"

echo
ok "Türkçe alias seti kuruldu."
warn "Yeni terminal açın veya: source $ALIASES"
