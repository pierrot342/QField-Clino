import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qgis

Item {
    id: plugin

    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    property var positionSource: iface.findItemByObjectName("positionSource")
    property var detectedLayer: null

    property string lastUniteObs: ""
    property string lastLithologie: ""
    property string lastFacies: ""
    property bool saving: false

    function fieldExists(layer, fieldName) {
        if (!layer || !layer.fields)
            return false
        return layer.fields.indexOf(fieldName) >= 0
    }

    function scoreLayer(layer) {
        if (!layer || !layer.fields)
            return -1
        var score = 0
        var expected = ["azimut", "pendage", "strike", "unite_obs", "unite_carte", "lithologie", "facies", "note", "date_heure"]
        for (var i = 0; i < expected.length; ++i) {
            if (fieldExists(layer, expected[i]))
                score += 10
        }
        if (layer.name && layer.name.toLowerCase().indexOf("pendage") >= 0)
            score += 20
        return score
    }

    function detectBestLayer() {
        detectedLayer = null
        var bestScore = -1
        var layers = iface.mapCanvas().mapSettings.layers
        for (var i = 0; i < layers.length; ++i) {
            var s = scoreLayer(layers[i])
            if (s > bestScore) {
                bestScore = s
                detectedLayer = layers[i]
            }
        }
        return detectedLayer
    }

    function gpsInfo() {
        if (!positionSource || !positionSource.active)
            return null
        var info = positionSource.positionInformation
        if (!info)
            return null
        var lon = Number(info.longitude)
        var lat = Number(info.latitude)
        if (!isFinite(lon) || !isFinite(lat))
            return null
        return { "info": info, "lon": lon, "lat": lat }
    }

    function updateGps() {
        var g = gpsInfo()
        if (!g) {
            gpsLabel.text = "GPS : position non disponible"
            return
        }
        gpsLabel.text = "GPS : " + g.lat.toFixed(6) + ", " + g.lon.toFixed(6)
    }

    function setAttributeIfPresent(feature, layer, fieldName, value) {
        if (fieldExists(layer, fieldName))
            feature.setAttribute(fieldName, value)
    }

    function refreshAfterSave(layer) {
        // Force QField/QGIS to rebuild the rendered layer after the committed feature.
        try {
            if (layer && layer.triggerRepaint)
                layer.triggerRepaint()
        } catch (e1) {}

        try {
            if (mapCanvas && mapCanvas.refreshAllLayers)
                mapCanvas.refreshAllLayers()
        } catch (e2) {}

        try {
            if (mapCanvas && mapCanvas.refresh)
                mapCanvas.refresh()
        } catch (e3) {}
    }

    function saveFeature() {
        if (saving)
            return
        saving = true

        try {
            var layer = detectBestLayer()
            if (!layer) {
                mainWindow.displayToast("ERREUR V0.7 : couche pendages introuvable")
                saving = false
                return
            }

            var g = gpsInfo()
            if (!g) {
                mainWindow.displayToast("ERREUR V0.7 : GPS non disponible")
                saving = false
                return
            }

            if (azimutField.text.trim() === "" || pendageField.text.trim() === "") {
                mainWindow.displayToast("ERREUR V0.7 : azimut et pendage obligatoires")
                saving = false
                return
            }

            var az = Number(azimutField.text)
            var dip = Number(pendageField.text)
            if (!isFinite(az) || !isFinite(dip)) {
                mainWindow.displayToast("ERREUR V0.7 : azimut/pendage invalides")
                saving = false
                return
            }

            var wgsGeometry = QfGeometryUtils.createGeometryFromWkt("POINT(" + g.lon + " " + g.lat + ")")
            var geometry = QfGeometryUtils.reprojectGeometry(
                        wgsGeometry,
                        QfCoordinateReferenceSystemUtils.wgs84Crs(),
                        layer.crs)

            if (!geometry) {
                mainWindow.displayToast("ERREUR V0.7 : création géométrie impossible")
                saving = false
                return
            }

            if (!layer.startEditing()) {
                mainWindow.displayToast("ERREUR V0.7 : couche non modifiable")
                saving = false
                return
            }

            var feature = QfFeatureUtils.createFeature(layer, geometry, g.info)
            if (!feature) {
                layer.rollBack()
                mainWindow.displayToast("ERREUR V0.7 : création entité impossible")
                saving = false
                return
            }

            setAttributeIfPresent(feature, layer, "azimut", az)
            setAttributeIfPresent(feature, layer, "pendage", dip)

            if (strikeField.text.trim() !== "") {
                var strikeValue = Number(strikeField.text)
                if (isFinite(strikeValue))
                    setAttributeIfPresent(feature, layer, "strike", strikeValue)
            }

            setAttributeIfPresent(feature, layer, "unite_obs", uniteObsField.text.trim())
            setAttributeIfPresent(feature, layer, "unite_carte", "")
            setAttributeIfPresent(feature, layer, "unite", uniteObsField.text.trim())
            setAttributeIfPresent(feature, layer, "lithologie", lithologieField.text.trim())
            setAttributeIfPresent(feature, layer, "facies", faciesField.text.trim())
            setAttributeIfPresent(feature, layer, "note", noteField.text.trim())
            setAttributeIfPresent(feature, layer, "date_heure", Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss"))

            if (!QfLayerUtils.addFeature(layer, feature)) {
                layer.rollBack()
                mainWindow.displayToast("ERREUR V0.7 : ajout de l'entité refusé")
                saving = false
                return
            }

            if (!layer.commitChanges()) {
                layer.rollBack()
                mainWindow.displayToast("ERREUR V0.7 : enregistrement GeoPackage impossible")
                saving = false
                return
            }

            lastUniteObs = uniteObsField.text.trim()
            lastLithologie = lithologieField.text.trim()
            lastFacies = faciesField.text.trim()

            refreshAfterSave(layer)

            mainWindow.displayToast("OK V0.7 — pendage enregistré et carte actualisée")

            azimutField.text = ""
            pendageField.text = ""
            strikeField.text = ""
            noteField.text = ""
            saving = false
            dialog.close()
        } catch (e) {
            saving = false
            mainWindow.displayToast("ERREUR V0.7 : " + e)
        }
    }

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(toolbarButton)
    }

    Component.onDestruction: {
        iface.removeItemFromPluginsToolbar(toolbarButton)
    }

    QfToolButton {
        id: toolbarButton
        iconSource: "qrc:/themes/qfield/nodpi/ic_measurement.svg"
        bgcolor: "#ffffff"
        onClicked: {
            detectBestLayer()
            updateGps()
            uniteObsField.text = lastUniteObs
            lithologieField.text = lastLithologie
            faciesField.text = lastFacies
            dialog.open()
        }
    }

    Dialog {
        id: dialog
        parent: mainWindow.contentItem
        modal: true
        title: "QField Clino v0.7 — Nouveau pendage"
        width: Math.min(mainWindow.width * 0.94, 560)
        height: Math.min(mainWindow.height * 0.90, 760)
        anchors.centerIn: parent

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: detectedLayer ? "Couche : " + detectedLayer.name : "Couche : non détectée"
                    wrapMode: Text.WordWrap
                }

                Label {
                    id: gpsLabel
                    Layout.fillWidth: true
                    text: "GPS : ..."
                    wrapMode: Text.WordWrap
                }

                Button {
                    text: "Actualiser GPS"
                    Layout.fillWidth: true
                    onClicked: updateGps()
                }

                Label { text: "Azimut (°)" }
                TextField {
                    id: azimutField
                    Layout.fillWidth: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    placeholderText: "ex. 135"
                }

                Label { text: "Pendage (°)" }
                TextField {
                    id: pendageField
                    Layout.fillWidth: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    placeholderText: "ex. 42"
                }

                Label { text: "Strike (°) — facultatif" }
                TextField {
                    id: strikeField
                    Layout.fillWidth: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    placeholderText: "facultatif"
                }

                Label { text: "Unité carte" }
                TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    placeholderText: "Automatique plus tard"
                }

                Label { text: "Unité observée" }
                TextField {
                    id: uniteObsField
                    Layout.fillWidth: true
                    placeholderText: "ex. Valanginien"
                }

                Label { text: "Lithologie" }
                TextField {
                    id: lithologieField
                    Layout.fillWidth: true
                    placeholderText: "ex. Calcaire"
                }

                Label { text: "Faciès" }
                TextField {
                    id: faciesField
                    Layout.fillWidth: true
                }

                Label { text: "Note" }
                TextArea {
                    id: noteField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    wrapMode: TextEdit.Wrap
                }

                Button {
                    Layout.fillWidth: true
                    enabled: !saving
                    text: saving ? "ENREGISTREMENT..." : "ENREGISTRER CE PENDAGE"
                    onClicked: saveFeature()
                }

                Button {
                    Layout.fillWidth: true
                    text: "Fermer"
                    enabled: !saving
                    onClicked: dialog.close()
                }
            }
        }
    }
}
