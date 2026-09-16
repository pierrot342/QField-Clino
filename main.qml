import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qgis
import Theme

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var detectedLayer: null
  property string diagnosticText: "Appuie sur Analyser le projet."

  property var wantedFields: ["azimut", "pendage", "strike", "unite", "lithologie", "facies", "note", "date_heure"]

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(clinoButton)
    mainWindow.displayToast("QField Clino v0.2 chargé")
  }

  function fieldNames(layer) {
    if (!layer || !layer.fields)
      return []
    try {
      return layer.fields.names
    } catch (e) {
      return []
    }
  }

  function fieldScore(layer) {
    const names = fieldNames(layer)
    let score = 0
    for (let i = 0; i < wantedFields.length; i++) {
      if (names.indexOf(wantedFields[i]) >= 0)
        score++
    }
    return score
  }

  function findBestLayer() {
    detectedLayer = null
    let layers = []
    try {
      layers = mapCanvas.mapSettings.layers
    } catch (e) {
      diagnosticText = "Impossible de lire les couches du projet : " + e
      return
    }

    let best = null
    let bestScore = -1
    for (let i = 0; i < layers.length; i++) {
      const layer = layers[i]
      if (!layer || !layer.fields)
        continue
      const score = fieldScore(layer)
      const lname = (layer.name || "").toLowerCase()
      const bonus = (lname.indexOf("pendage") >= 0 || lname.indexOf("clino") >= 0) ? 2 : 0
      if (score + bonus > bestScore) {
        best = layer
        bestScore = score + bonus
      }
    }

    if (!best) {
      diagnosticText = "Aucune couche vectorielle exploitable détectée."
      return
    }

    detectedLayer = best
    const names = fieldNames(best)
    let lines = []
    lines.push("Couche : " + best.name)

    try {
      lines.push("SCR : " + best.crs.authid())
    } catch (e) {
      lines.push("SCR : non lisible")
    }

    lines.push("")
    lines.push("Champs :")
    for (let j = 0; j < wantedFields.length; j++) {
      const f = wantedFields[j]
      lines.push((names.indexOf(f) >= 0 ? "✓ " : "✗ ") + f)
    }

    if (fieldScore(best) >= 3)
      lines.push("\nPrêt pour la prochaine étape : création d'un pendage.")
    else
      lines.push("\nCouche trouvée, mais trop peu de champs Clino sont reconnus.")

    diagnosticText = lines.join("\n")
  }

  QfToolButton {
    id: clinoButton
    iconSource: Theme.getThemeVectorIcon("ic_explore_white_24dp")
    iconColor: Theme.toolButtonColor
    bgcolor: Theme.toolButtonBackgroundColor
    round: true
    onClicked: {
      findBestLayer()
      clinoDialog.open()
    }
  }

  Dialog {
    id: clinoDialog
    parent: mainWindow.contentItem
    modal: true
    title: "QField Clino v0.2"
    standardButtons: Dialog.Ok
    width: Math.min(parent.width - 24, 460)
    x: (parent.width - width) / 2
    y: Math.max(12, (parent.height - height) / 2)

    ColumnLayout {
      width: parent.width
      spacing: 12

      Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: diagnosticText
      }

      Button {
        Layout.fillWidth: true
        text: "Analyser le projet"
        onClicked: findBestLayer()
      }
    }
  }
}
