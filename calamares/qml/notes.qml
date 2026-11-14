// ============================================================================
//  MacNix 2.0 — Calamares notesqml ekranı
// ============================================================================
//  TASARIM KURALI (canlı testte öğrenildi): bu dosya MÜMKÜN OLDUĞUNCA BASİT
//  olmalı. Debian'ın minimal Calamares kurulumunda:
//   • QtQuick.Controls / Layouts / Window modülleri eksik olabiliyor →
//     "module ... is not installed" → modül yüklenemez → kurulum açılmaz.
//   • Repeater + satır içi nesne dizisi (model: [{...}]) gibi yapılar
//     bu ortamda Calamares'i ÇÖKERTTİ (hata mesajı bile yazmadan kapandı).
//  Bu yüzden QML yalnızca QtQuick + iki Text öğesi kullanır: en düşük risk.
// ----------------------------------------------------------------------------
import QtQuick 2.12

Item {
    id: notesRoot
    width: parent ? parent.width : 800
    height: parent ? parent.height : 600

    Text {
        id: title
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        wrapMode: Text.WordWrap
        font.pixelSize: 18
        font.bold: true
        color: "#1f2933"
        text: qsTr("MacNix 2.0 — Gelişmiş macOS Sanallaştırma Distrosu")
    }

    Text {
        id: subtitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: title.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 2
        wrapMode: Text.WordWrap
        font.pixelSize: 10
        color: "#52606d"
        text: qsTr("BELGESELSEMO tarafından ARENA.AI sayesinde geliştirildi · " +
                   "github.com/local-over/macnix orijinal reposundan fork edilerek " +
                   "· belgeselsemo.com.tr")
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: subtitle.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 16
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        color: "#3d4852"
        text: qsTr(
            "Bu ekran kurulumun sonunda ne olacağını dürüstçe anlatır. " +
            "Hiçbir uyarı kurulumu engellemez.\n\n" +

            "1) macOS NASIL ÇALIŞACAK?\n" +
            "MacNix, macOS'u QEMU/KVM sanal makinesinde çalıştırır. Apple " +
            "donanımı taklit edilmez; kendi donanımınızda sanallaştırma " +
            "kullanılır.\n\n" +

            "2) EKRAN KARTI (GPU) DURUMU\n" +
            "GPU passthrough yalnızca macOS sürücüsü bulunan AMD kartlarda " +
            "çalışır. Sürücüsü olmayan kartlarda sistem yazılım render " +
            "(virtio-gpu) ile çalışır: masaüstü ve uygulamalar akıcıdır, " +
            "oyun ve video hızlandırma olmaz. Kurulum sonrası macnix-doctor " +
            "hangi modda olduğunuzu söyler.\n\n" +

            "3) KURULUMDAN SONRA NE OLACAK?\n" +
            "Makine yeniden başlar; ilk açılışta MacNix Kurulum Sihirbazı " +
            "(macnix-setup) macOS kurtarma imajını Apple sunucularından " +
            "indirir (yaklaşık 700 MB) ve macOS kurulumu başlar. İnternet " +
            "bağlantısı yeterlidir.\n\n" +

            "4) DİSK VE BELLEK\n" +
            "En az 25 GB boş disk ve 4 GB RAM gerekir. Sanal makineye " +
            "ayrılacak çekirdek/RAM, donanımınıza göre kurulum sırasında " +
            "otomatik belirlenir.\n\n" +

            "5) SORUN ÇIKARSA\n" +
            "macnix-doctor ile tanılama, macnix-log --tar ile günlük paketi " +
            "alınır. Metin modunda kurulum: sudo macnix-tui. Alternatif " +
            "konsol: Ctrl+Alt+F2.")
    }
}
