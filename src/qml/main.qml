import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtWebEngine
import Qt5Compat.GraphicalEffects
import Cutie
import Qt.labs.settings

CutieWindow {
    id: window
    width: 640
    height: 480
    visible: true
    title: qsTr("Browser")

    property string browserURL: ""
    property bool webApp: false

    Settings {
        id: settings
        category: "CutieBrowser"
        property string downloadsHistory: ""
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function statusText(status) {
        return status === "completed" ? qsTr("Completed")
             : status === "downloading" ? qsTr("Downloading…")
             : status === "cancelled" ? qsTr("Cancelled")
             : qsTr("Failed");
    }

    function indexOfDownload(did) {
        for (var i = 0; i < downloadsModel.count; i++)
            if (downloadsModel.get(i).did === did) return i;
        return -1;
    }

    function saveDownloads() {
        var arr = [];
        for (var i = 0; i < downloadsModel.count; i++) {
            var item = downloadsModel.get(i);
            // Don't persist active downloading state as "downloading" across restarts
            var st = item.status === "downloading" ? "failed" : item.status;
            arr.push({did: item.did, name: item.name, path: item.path, status: st});
        }
        settings.downloadsHistory = JSON.stringify(arr);
    }

    function loadDownloads() {
        if (settings.downloadsHistory === "") return;
        try {
            var arr = JSON.parse(settings.downloadsHistory);
            for (var i = 0; i < arr.length; i++) {
                var r = arr[i];
                downloadsModel.append({
                    did: r.did,
                    name: r.name,
                    path: r.path,
                    status: r.status,
                    progress: r.status === "completed" ? 1 : 0
                });
            }
        } catch (e) {
            console.log("Error loading download history:", e);
        }
    }

    function setDownloadStatus(did, status) {
        var i = indexOfDownload(did);
        if (i < 0 || downloadsModel.get(i).status !== "downloading") return;
        downloadsModel.setProperty(i, "status", status);
        if (status === "completed") downloadsModel.setProperty(i, "progress", 1);
        saveDownloads();
    }

    function trackDownload(download) {
        var did = Date.now() + "-" + download.id;
        var name = download.downloadFileName;
        var path = download.downloadDirectory + "/" + name;
        downloadsModel.insert(0, {did: did, name: name, path: path, status: "downloading", progress: 0});
        saveDownloads();

        download.receivedBytesChanged.connect(function() {
            var i = indexOfDownload(did);
            if (i < 0) return;
            downloadsModel.setProperty(i, "progress", download.totalBytes > 0 ? download.receivedBytes / download.totalBytes : 0);
        });
        download.stateChanged.connect(function() {
            if (download.state === WebEngineDownloadRequest.DownloadCompleted)
                setDownloadStatus(did, "completed");
            else if (download.state === WebEngineDownloadRequest.DownloadCancelled)
                setDownloadStatus(did, "cancelled");
            else if (download.state === WebEngineDownloadRequest.DownloadInterrupted)
                setDownloadStatus(did, "failed");
        });
    }

    function clearDownloads() {
        for (var i = downloadsModel.count - 1; i >= 0; i--)
            if (downloadsModel.get(i).status !== "downloading")
                downloadsModel.remove(i);
        saveDownloads();
    }

    Component.onCompleted: loadDownloads()

    function fixUrl(url) {
        url = url.replace( /^\s+/, "").replace( /\s+$/, ""); // remove white space
        url = url.replace( /(<([^>]+)>)/ig, ""); // remove <b> tag 
        if (url == "") return url;
        if (url[0] == "/") { return "file://"+url; }
        if (url[0] == '.') { 
            var str = itemMap[currentTab].url.toString();
            var n = str.lastIndexOf('/');
            return str.substring(0, n)+url.substring(1);
        }
        //FIXME: search engine support here
        if (url.startsWith('chrome://')) { return url; } 
        if (url.indexOf('.') < 0) { return "https://duckduckgo.com/?q="+url; }
        if (url.indexOf(":") < 0) { return "https://"+url; } 
        else { return url;}
    }

    function browse(url) {
        webview.url = fixUrl(url);
    }

    initialPage: CutiePage {
        id: iPage

        Item { 
            id: headerBar
            height: webApp ? 0 : 44
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !webApp
            CutieButton {
                id: backButton
                width: 28
                height: width
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                enabled: webview.canGoBack
                background: null
                icon.name: "go-previous-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: {
                    webview.goBack()
                }
            }

            CutieButton {
                id: forwardButton
                width: 28
                height: width
                anchors.left: backButton.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                enabled: webview.canGoForward
                background: null
                icon.name: "go-next-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: {
                    webview.goForward()
                }
            }

            CutieButton {
                id: menuButton
                width: 28
                height: width
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                background: null
                icon.name: "view-more-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: moreMenu.open()
            }

            CutieMenu {
                id: moreMenu
                y: -height - 10
                CutieMenuItem {
                    text: qsTr("Downloads")
                    onTriggered: downloadsPanel.visible = true
                }
            }

            CutieTextField {
                id: urlText
                anchors.left: forwardButton.right
                anchors.right: menuButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: ""

                Connections {
                    target: window
                    function onBrowserURLChanged () {
                        urlText.text = window.browserURL;
                    }
                }

                onAccepted: browse(text)

                onFocusChanged: {
                    if (focus) urlFocusTimer.start();
                }

                Timer {
                    id: urlFocusTimer
                    interval: 0
                    running: false
                    repeat: false
                    onTriggered: {
                        urlText.selectAll();
                    }
                }
            }
            Rectangle {
                id: urlProgressBar
                height: 3
                visible: webview.loadProgress < 100
                width: parent.width * (webview.loadProgress / 100)
                anchors.top: headerBar.bottom
                anchors.left: parent.left
                color: Atmosphere.textColor
            }

        }
        ListModel { id: downloadsModel }

        Item {
            id: downloadsPanel
            z: 20
            visible: false
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: headerBar.top

            MouseArea { anchors.fill: parent }

            FastBlur {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: webview.height
                source: webview
                radius: 70
            }

            Rectangle {
                anchors.fill: parent
                color: Atmosphere.primaryColor
                opacity: 0.6
            }

            CutiePageHeader {
                id: downloadsHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                title: qsTr("Downloads")
            }

            CutieListView {
                anchors.top: downloadsHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true
                model: downloadsModel

                menu: CutieMenu {
                    CutieMenuItem {
                        text: qsTr("Clear finished")
                        onTriggered: clearDownloads()
                    }
                    CutieMenuItem {
                        text: qsTr("Close")
                        onTriggered: downloadsPanel.visible = false
                    }
                }

                delegate: CutieListItem {
                    text: model.name
                    subText: statusText(model.status) + " — " + model.path
                    wrapMode: Text.NoWrap
                    elide: Text.ElideMiddle
                    onClicked: {
                        if (model.status === "completed")
                            Qt.openUrlExternally(fileUrl(model.path))
                    }

                    Rectangle {
                        visible: model.status === "downloading"
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        anchors.left: parent.left
                        anchors.leftMargin: 36
                        height: 3
                        radius: 2
                        width: (parent.width - 72) * model.progress
                        color: Atmosphere.accentColor
                    }
                }
            }

            CutieLabel {
                anchors.centerIn: parent
                visible: downloadsModel.count === 0
                text: qsTr("No downloads")
            }
        }

        WebEngineView {
            id: webview
            settings.webRTCPublicInterfacesOnly: true
            settings.touchIconsEnabled: true
            settings.spatialNavigationEnabled: true
            settings.screenCaptureEnabled: true
            settings.printElementBackgrounds: true
            settings.playbackRequiresUserGesture: true
            settings.localContentCanAccessRemoteUrls: true
            settings.linksIncludedInFocusChain: true
            settings.localContentCanAccessFileUrls: true
            settings.allowGeolocationOnInsecureOrigins: true
            settings.allowRunningInsecureContent: true
            settings.allowWindowActivationFromJavaScript: true
            settings.autoLoadIconsForPage: true
            settings.errorPageEnabled: true
            settings.focusOnNavigationEnabled: true
            settings.hyperlinkAuditingEnabled: true
            settings.javascriptCanPaste: true
            settings.javascriptCanOpenWindows: true
            settings.javascriptCanAccessClipboard: true
            settings.localStorageEnabled: true
            settings.pluginsEnabled: true
            settings.showScrollBars: false
            settings.webGLEnabled: true
            settings.fullScreenSupportEnabled: true
            settings.javascriptEnabled: true
            settings.autoLoadImages: true
            settings.accelerated2dCanvasEnabled: true
            url: "https://start.duckduckgo.com"
            transformOrigin: Item.Center
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -23 * !webApp
            width: parent.width
            height: parent.height -46 * !webApp
            
            profile: WebEngineProfile {
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                storageName: "CutieBrowser"
                httpUserAgent: "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.76 Mobile Safari/537.36"

                onDownloadRequested: function(download) {
                    download.accept()
                    trackDownload(download)
                }
            }
            
            onLoadingChanged: {
                window.browserURL = webview.url;
                zoomFactor =  6;
            }
        }
    }
}