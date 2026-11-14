# ============================================================================
#  MacNix 2.0 — bitiş ekranı (finishedq)
# ============================================================================
#  Canlı test HATASI: standart "finished" modülünde ilerleme düğmesi her zaman
#  PASİF (FinishedViewStep::isNextEnabled() -> false) ve Calamares'i kapatmak
#  için tek yol pencereyi kapatmaktı. Üstelik yeniden başlatma onay kutusu
#  işaretli olmasına rağmen "Continue" tıklanabilir görünmüyordu.
#
#  finishedq + marka dizinindeki finishedq.qml:
#   • "Bitir ve Yeniden Başlat"  → restartNowWanted = true; ViewManager.quit()
#   • "Yeniden başlatmadan bitir" → yalnızca kapatır
#   • 30 saniyelik geri sayım → kimse dokunmazsa kendini kapatır ve makine
#     yeniden başlar (kurulum sonrası macOS kurulumu böylece kendiliğinden
#     başlar; kullanıcıdan hiçbir şey istenmez).
#
#  YENİDEN BAŞLATMA MEKANİZMASI DEĞİŞMEDİ: uygulama kapanırken Calamares'in
#  finished modülü restartNowCommand'i çalıştırır (Calamares 3.2.61 kaynağında
#  doğrulandı: connect(qApp, aboutToQuit, Config::doRestart)).
# ----------------------------------------------------------------------------
---
qmlSearch: branding
qmlFilename: "finishedq"

# user-unchecked: onay kutusu yok, "Bitir" ile kapanınca yeniden BAŞLATMAZ.
# (QML'de restartNowWanted açıkça true yapılırsa yeniden başlatır.)
restartNowMode: user-unchecked
restartNowCommand: "systemctl -i reboot"
notifyOnFinished: false
