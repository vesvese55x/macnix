# ============================================================================
#  MacNix 2.0 — karşılama ekranı (welcomeq)
# ============================================================================
#  NEDEN welcomeq? Yerleşik "welcome" modülünün C++ ekranı sabittir: logo ile
#  metin çakışıyordu ve alt kredi şeridi pencere dışına taşıyordu (canlı test
#  z1.png / g1.png). welcomeq, marka dizinindeki welcome.qml dosyasını yükler;
#  böylece "Gelişmiş macOS Sanallaştırma Distrosu" tanımı ve fork/kredi bilgisi
#  tam denetimimizde olur.
#
#  NOT: qmlFilename ".qml" UZANTISI OLMADAN yazılır (Calamares uzantıyı
#  kendisi ekler). 2026-11-14 canlı VM testinde "welcome.qml" yazıldığı için
#  modül boş QML ile açıldı → ekranda "Welcome Loading failed." görüldü.
#
#  NOT: Bu modülün yapılandırma dosyası Calamares'te "welcomeq.conf" adıyla da
#  çalışır; Biz .py uzantısını kullanıyoruz çünkü Debian'ın calamares paketi
#  modül yapılandırmasını adıyla arar (settings.conf -> module-conf/%1.conf
#  ya da %1.py). İkisi de aynı YAML'ı okur.
#
#  Gereksinim denetimleri: internet YOK (MacNix çevrimdışı da kurulabilmeli),
#  ekran denetimi var (grafik ortam olmadan Calamares açılmaz).
---
qmlSearch: branding
qmlFilename: "welcome"

showSupportUrl:         false
showKnownIssuesUrl:     false
showReleaseNotesUrl:    false
showDonateUrl:          false

# Zorunlu ve önerilen koşullar. Depolama: en az 25 GB (macOS VM'i için).
requirements:
    requiredStorage:    25
    requiredRam:        4.0
    check:
        - storage
        - ram
        - root
        - screen
    required:
        - storage
        - root
