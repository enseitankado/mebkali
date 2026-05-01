# mebkali

Türkiye Milli Eğitim Bakanlığı (MEB) ağında — TLS-MITM yapan ve sadece HTTPS/HTTP/MEB-DNS açık tutan firewall arkasında — taze kurulmuş bir **Kali Linux 2026.1** VirtualBox sanal makinesini, **6 idempotent adımda** kullanılabilir hale getiren orkestratör.

> Eğitim ortamlarında kurumsal ağa bağlı Kali makineleri için tasarlandı. Kullanım amacı: yetkili sızma-testi/CTF/eğitim ortamlarında temel araçların (curl, git, apt, python, firefox, chromium, whois, dnsenum, theHarvester...) çalışır olmasını sağlamak.

## Çözdüğü problemler

| # | Adım | Aşılan engel |
|---|---|---|
| 1 | `01-mitm-cert-trust.sh` | MEB'in `fatihca` MITM kök sertifikasını sistem CA bundle, p11-kit, Firefox NSS, Chromium NSS olmak üzere **4 trust deposuna** kurar. Python 3.13'ün `VERIFY_X509_STRICT` davranışı için apt-upgrade-proof bir `ssl`/`urllib3` yaması bırakır. |
| 2 | `02-apt-mirror-fix.sh` | `http.kali.org` HTTP/503 verdiğinde **11 yedekli mirror** arasından HTTPS InRelease testi geçen ilkine geçer. Başarısız olursa otomatik revert. |
| 3 | `03-turkce-locale-keyboard.sh` | Türkçe locale (`tr_TR.UTF-8`) + Q klavye, **3 katmanda**: TTY (`vconsole.conf`), X11 (`localectl` + `/etc/default/keyboard`), LightDM. |
| 4 | `04-ntp-tz-format.sh` | `Europe/Istanbul` saat dilimi + `systemd-timesyncd`'a **4 primary + 6 fallback** NTP. RTC UTC. XFCE saat plugin 24h. |
| 5 | `05-vbox-host-paylasim.sh` | Host ↔ Guest dosya/pano paylaşımı için VirtualBox Guest Additions hipervizör IPC altyapısını doğrular (paketler MEB firewall'una hiç çıkmaz). |
| 6 | `06-firewall-bypass-rdap.sh` | `whois` (TCP/43) bloklu olduğunda RDAP-HTTPS muadiline yönlendirir; `theHarvester` ve `dnsenum` için MEB-uyumlu kullanım notları. |

## Hızlı başlangıç

```bash
git clone https://github.com/<USER>/mebkali.git
cd mebkali
bash mebkali.sh           # interaktif (her adımda E/h/q onayı)
bash mebkali.sh -y        # tüm adımlar onaysız
```

> **Sudo şifresi**: Default `kali`. Farklıysa `SUDO_PASS=<şifre> bash mebkali.sh`.

## Öne çıkan tasarım kararları

- **Idempotent**: yarıda kesilirse tekrar çalıştırın; var olanı yeniden uygulamaz.
- **Taşınabilir**: MEB kök sertifikası (`MEB_SERTIFIKASI.crt`) ve `libnss3-tools_*.deb` repoda paketli — apt henüz çalışmıyorken bile sertifika kurulumu tamamlanır.
- **Apt-upgrade-proof Python yaması**: `/usr/lib/python3/dist-packages/meb_mitm_fix.{py,pth}` versiyonsuz path; minor Python upgrade'lerinde bile aktif kalır.
- **Sağ-kenar-yok kutu UI**: Türkçe karakter ve emoji genişlik tutarsızlıklarını tasarımla baypas eder.
- **`-y` bayrağı**: CI/headless senaryolar için onay sorularını atlar.

## Adım scriptleri tek başına çalışır

`mebkali.sh` orkestratörden bağımsız olarak her adım scripti tek başına çalıştırılabilir:

```bash
sudo bash 01-mitm-cert-trust.sh
sudo bash 06-firewall-bypass-rdap.sh --diagnose
sudo bash 05-vbox-host-paylasim.sh --print-host-cmds
```

## Gereksinimler

- Kali Linux 2026.1 (rolling) — başka Debian türevlerinde minor port gerekir.
- VirtualBox 7.x guest (Step 5 için; diğer adımlar bağımsız).
- ~20 MB disk, ~10 MB ek paket indirmesi.

## Kurulduktan sonra manuel adımlar

- **Logout → Login** (locale + keymap + grup üyeliklerinin oturuma yansıması için).
- **Host VBox**: GUI'den iki yönlü pano + paylaşılan klasör tanımla — komutlar:

  ```bash
  bash 05-vbox-host-paylasim.sh --print-host-cmds
  ```

## Lisans

MIT — bkz. `LICENSE`.

## Sorumluluk reddi

Bu repo, *yetkili* eğitim/sızma-testi ortamlarında kullanılmak üzere hazırlanmıştır. MEB MITM sertifikasını sisteme kurmak, MEB ağında yapılan TLS bağlantılarınızın MEB tarafından gözlemlenebileceğini kabul ettiğiniz anlamına gelir. Hassas işlemler (banking, kişisel hesaplar) için bu makineyi MEB ağında kullanmayın.
