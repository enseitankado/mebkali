# mebkali

Okul ağında kullanılan bir Kali makinesi taze kurulduğunda, internete bağlansa bile pek çok aracı çalışmaz hale gelir: tarayıcı sertifika hatası verir, `apt` paket indiremez, `git clone` başarısız olur, Python betikleri yarıda kesilir, hatta `whois` gibi temel araçlar bile bağlanamaz. Bunun nedeni MEB ağının internet trafiğini denetlemek için arada durup TLS bağlantılarını kendi sertifikasıyla yeniden imzalaması ve birçok portu kapalı tutmasıdır. Bu sorunları el ile tek tek çözmek hem zaman alıcı hem de ileride yeni bir makine kurulduğunda her şeyi baştan tekrar yapmak gerekir.

**mebkali**, Kali makinesini bu ortamda kullanılır hale getirmek için gereken her şeyi 6 adımda otomatik yapan bir yardımcı betiktir. MEB kök sertifikasını uygun yerlere kurar, çalışan bir paket sunucusu bulur, Türkçe yerel ayarları ve Q klavyeyi etkinleştirir, saati doğru ayarlar, sanal makineyle ana bilgisayar arasında dosya/pano paylaşımını hazırlar ve engellenen araçlar için yedek yöntemler kurar. Her adımdan önce ne yapılacağını ve hangi engeli aştığını size anlatır, ardından onayınızı alır; istediğiniz adımı atlayabilir, betiği yarıda kesip daha sonra kaldığınız yerden devam edebilirsiniz.

## Çözdüğü problemler

| # | Adım | Aşılan engel |
|---|---|---|
| 1 | `01-mitm-cert-trust.sh` | MEB kök sertifikasını **4 ayrı güven deposuna** ekler: sistem geneli sertifika havuzu, Firefox sertifika veritabanı, Chromium sertifika veritabanı, Python'un kendi denetimi. Python'un katı sertifika kontrolü için paket güncellemelerinden etkilenmeyecek bir yama bırakır. |
| 2 | `02-apt-mirror-fix.sh` | Varsayılan paket sunucusu yanıt vermediğinde, **11 yedekli sunucu** arasından çalışan ilkine geçer. Yapılandırma yedeklenir; bir sorun çıkarsa otomatik geri alınır. |
| 3 | `03-turkce-locale-keyboard.sh` | Türkçe yerel ayarları (`tr_TR.UTF-8`) ve Türkçe Q klavyeyi **3 katmanda** kurar: terminal (TTY), grafik ortam (X11) ve oturum açma ekranı (LightDM). |
| 4 | `04-ntp-tz-format.sh` | Saat dilimini `Europe/Istanbul` yapar; zaman senkronizasyonu için **4 birincil + 6 yedek** sunucu yazar. Donanım saati UTC'de tutulur (Windows ile çift kurulumda saat karışmaz); ekran saati 24 saat biçiminde. |
| 5 | `05-vbox-host-paylasim.sh` | Sanal makine ile ana bilgisayar arasında dosya ve pano paylaşımını hipervizör IPC üzerinden hazırlar — paketler ağdan hiç çıkmaz, MEB'in görüş alanı dışındadır. |
| 6 | `06-firewall-bypass-rdap.sh` | `whois` engelli olduğunda RDAP (HTTPS üzerinden çalışan muadili) sarmalayıcı betik kurar; `theHarvester` ve `dnsenum` için MEB ağında çalışacak alternatif kullanım yöntemleri yazdırır. |

## Yükleme

```bash
git clone https://github.com/<USER>/mebkali.git
cd mebkali
bash mebkali.sh           # her adımda E/h/q onayı
bash mebkali.sh -y        # tüm adımlar onaysız (otomatik evet)
```

> **Sudo şifresi**: Varsayılan `kali`. Farklıysa `SUDO_PASS=<şifre> bash mebkali.sh`.

Onay sorgusunda:
- `E` (varsayılan) — adımı uygula
- `h` — atla
- `q` — buraya kadar olanları bırak ve özetle çık

Betikler **yeniden çalıştırılabilir**: yarıda keserseniz veya tekrar çalıştırırsanız zarar vermez; daha önce kurulmuş bir şeyi tekrar kurmaz.

## Adım betikleri tek başına çalışır

`mebkali.sh` yönetici betikten bağımsız olarak her adım tek başına çalıştırılabilir:

```bash
sudo bash 01-mitm-cert-trust.sh
sudo bash 06-firewall-bypass-rdap.sh --diagnose
sudo bash 05-vbox-host-paylasim.sh --print-host-cmds
```

## Kurulduktan sonra manuel adımlar

- **Oturumu kapat → aç** (yerel ayar, klavye düzeni ve grup üyeliklerinin yeni oturuma yansıması için).
- **Ana makinede VirtualBox**: GUI'den iki yönlü pano + paylaşılan klasörü tanımla — komutlar:

  ```bash
  bash 05-vbox-host-paylasim.sh --print-host-cmds
  ```

## Lisans

MIT — bkz. `LICENSE`.

## Sorumluluk reddi

Bu repo, *yetkili* eğitim ortamlarında kullanılmak üzere hazırlanmıştır. MEB kök sertifikasını sisteme kurmak, MEB ağında yapılan TLS bağlantılarınızın MEB tarafından gözlemlenebileceğini kabul ettiğiniz anlamına gelir. Hassas işlemler (bankacılık, kişisel hesaplar) için bu makineyi MEB ağında kullanmayın.
