import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qgis
import org.qfield.core
import Theme

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var positionSource: iface.findItemByObjectName("positionSource")
  property var detectedLayer: null

  property string lastUniteObs: ""
  property string lastLithologie: ""
  property string lastFacies: ""
  property string gpsText: "GPS non vérifié"
  property bool saving: false

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(clinoButton)
    mainWindow.displayToast("QField Clino v0.6 chargé")
  }

  function fieldNames(layer) {
    if (!layer || !layer.fields) return []
    try { return layer.fields.names } catch (e) { return [] }
  }

  function scoreLayer(layer) {
    const n = fieldNames(layer)
    let s = 0
    const wanted = ["azimut", "pendage", "strike", "unite_obs", "unite_carte", "lithologie", "facies", "note", "date_heure"]
    for (let i = 0; i < wanted.length; i++) {
      if (n.indexOf(wanted[i]) >= 0) s++
    }
    const name = (layer.name || "").toLowerCase()
    if (name.indexOf("pendage") >= 0 || name.indexOf("clino") >= 0) s += 2
    return s
  }

  function findLayer() {
    let layers = []
    try { layers = mapCanvas.mapSettings.layers } catch (e) { return null }

    let best = null
    let bestScore = -1
    for (let i = 0; i < layers.length; i++) {
      const l = layers[i]
      if (!l || !l.fields) continue
      const s = scoreLayer(l)
      if (s > bestScore) {
        best = l
        bestScore = s
      }
    }
    detectedLayer = best
    return best
  }

  function updateGps() {
    if (!positionSource || !positionSource.active) {
      gpsText = "GPS inactif — active le positionnement QField"
      return false
    }

    const info = positionSource.positionInformation
    if (!info || !info.longitudeValid || !info.latitudeValid) {
      gpsText = "GPS actif, mais pas encore de position valide"
      return false
    }

    gpsText = "GPS : " + Number(info.latitude).toFixed(6) + ", " + Number(info.longitude).toFixed(6)
    return true
  }

  function prepareForm() {
    findLayer()
    updateGps()
    uniteObs.text = lastUniteObs
    lithologie.text = lastLithologie
    facies.text = lastFacies
    uniteCarte.text = ""
    saving = false
  }

  function setAttributeIfPresent(feature, layer, name, value) {
    const idx = layer.fields.indexOf(name)
    if (idx >= 0) feature.setAttribute(idx, value)
  }

  function parseRequiredNumber(text, label, minValue, maxValue) {
    if (String(text).trim() === "") {
      mainWindow.displayToast(label + " obligatoire")
      return null
    }
    const v = Number(text)
    if (!isFinite(v) || v < minValue || v > maxValue) {
      mainWindow.displayToast(label + " invalide (" + minValue + " à " + maxValue + "°)")
      return null
    }
    return Math.round(v)
  }

  function saveFeature() {
    if (saving) return
    saving = true

    try {
      const layer = detectedLayer || findLayer()
      if (!layer) {
        mainWindow.displayToast("ERREUR : couche de pendages introuvable")
        saving = false
        return
      }

      if (!updateGps()) {
        mainWindow.displayToast("ERREUR : pas de position GPS valide")
        saving = false
        return
      }

      const az = parseRequiredNumber(azimut.text, "Azimut", 0, 359)
      if (az === null) { saving = false; return }
      const dip = parseRequiredNumber(pendage.text, "Pendage", 0, 90)
      if (dip === null) { saving = false; return }

      let str = null
      if (String(strike.text).trim() !== "") {
        const s = Number(strike.text)
        if (!isFinite(s) || s < 0 || s > 359) {
          mainWindow.displayToast("Strike invalide (0 à 359°)")
          saving = false
          return
        }
        str = Math.round(s)
      }

      const info = positionSource.positionInformation
      const lon = Number(info.longitude)
      const lat = Number(info.latitude)

      // Construit d'abord une géométrie WGS84 sans accéder aux propriétés x/y d'un QgsPoint.
      const wgsGeometry = QfGeometryUtils.createGeometryFromWkt("POINT(" + lon + " " + lat + ")")
      const geometry = QfGeometryUtils.reprojectGeometry(wgsGeometry, QfCoordinateReferenceSystemUtils.wgs84Crs(), layer.crs)

      if (!geometry) {
        mainWindow.displayToast("ERREUR : géométrie GPS impossible à créer")
        saving = false
        return
      }

      // Même séquence que les tests officiels QField : startEditing -> feature -> addFeature -> commitChanges.
      if (!layer.startEditing()) {
        mainWindow.displayToast("ERREUR : couche non modifiable")
        saving = false
        return
      }

      let feature = QfFeatureUtils.createFeature(layer, geometry, info)
      setAttributeIfPresent(feature, layer, "azimut", az)
      setAttributeIfPresent(feature, layer, "pendage", dip)
      if (str !== null) setAttributeIfPresent(feature, layer, "strike", str)
      setAttributeIfPresent(feature, layer, "unite_carte", uniteCarte.text)
      setAttributeIfPresent(feature, layer, "unite_obs", uniteObs.text)
      setAttributeIfPresent(feature, layer, "lithologie", lithologie.text)
      setAttributeIfPresent(feature, layer, "facies", facies.text)
      setAttributeIfPresent(feature, layer, "note", note.text)
      setAttributeIfPresent(feature, layer, "date_heure", new Date().toISOString())

      const added = QfLayerUtils.addFeature(layer, feature)
      if (!added) {
        layer.rollBack()
        mainWindow.displayToast("ERREUR : ajout du point refusé")
        saving = false
        return
      }

      const committed = layer.commitChanges()
      if (!committed) {
        layer.rollBack()
        mainWindow.displayToast("ERREUR : sauvegarde GeoPackage refusée")
        saving = false
        return
      }

      lastUniteObs = uniteObs.text
      lastLithologie = lithologie.text
      lastFacies = facies.text

      mainWindow.displayToast("OK — pendage enregistré dans " + layer.name)
      clinoDialog.close()

      azimut.text = ""
      pendage.text = ""
      strike.text = ""
      note.text = ""
      saving = false
    } catch (e) {
      saving = false
      mainWindow.displayToast("ERREUR V0.6 : " + e)
    }
  }

  QfToolButton {
    id: clinoButton
    iconSource: Theme.getThemeVectorIcon("ic_explore_white_24dp")
    iconColor: Theme.toolButtonColor
    bgcolor: Theme.toolButtonBackgroundColor
    round: true
    onClicked: {
      prepareForm()
      clinoDialog.open()
    }
  }

  Dialog {
    id: clinoDialog
    parent: mainWindow.contentItem
    modal: true
    title: "QField Clino v0.6 — Nouveau pendage"
    width: Math.min(parent.width - 20, 500)
    height: Math.min(parent.height - 30, 760)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    ScrollView {
      anchors.fill: parent
      contentWidth: availableWidth

      ColumnLayout {
        width: parent.width
        spacing: 8

        Label {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: detectedLayer ? "Couche : " + detectedLayer.name : "Couche pendages non détectée"
        }
        Label {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: gpsText
        }
        Button {
          Layout.fillWidth: true
          text: "Actualiser GPS"
          onClicked: updateGps()
        }

        Label { text: "Azimut (°)" }
        TextField { id: azimut; Layout.fillWidth: true; inputMethodHints: Qt.ImhFormattedNumbersOnly; placeholderText: "ex. 135" }

        Label { text: "Pendage (°)" }
        TextField { id: pendage; Layout.fillWidth: true; inputMethodHints: Qt.ImhFormattedNumbersOnly; placeholderText: "ex. 42" }

        Label { text: "Strike (°)" }
        TextField { id: strike; Layout.fillWidth: true; inputMethodHints: Qt.ImhFormattedNumbersOnly; placeholderText: "facultatif" }

        Label { text: "Unité carte" }
        TextField { id: uniteCarte; Layout.fillWidth: true; readOnly: true; placeholderText: "automatique avec carte géologique (plus tard)" }

        Label { text: "Unité observée" }
        TextField { id: uniteObs; Layout.fillWidth: true; placeholderText: "ex. Valanginien" }

        Label { text: "Lithologie" }
        TextField { id: lithologie; Layout.fillWidth: true; placeholderText: "ex. Calcaire" }

        Label { text: "Faciès" }
        TextField { id: facies; Layout.fillWidth: true; placeholderText: "ex. bioclastique" }

        Label { text: "Note" }
        TextArea { id: note; Layout.fillWidth: true; Layout.preferredHeight: 80; wrapMode: TextEdit.Wrap; placeholderText: "Observation libre" }

        Button {
          Layout.fillWidth: true
          text: saving ? "ENREGISTREMENT..." : "ENREGISTRER CE PENDAGE"
          enabled: detectedLayer !== null && !saving
          onClicked: saveFeature()
        }

        Label {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: "V0.6 : écriture GeoPackage contrôlée, reprojection de la géométrie complète et protection contre les doubles clics."
        }
      }
    }
  }
}
