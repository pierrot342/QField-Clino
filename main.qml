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
  property var positionSource: iface.findItemByObjectName("positionSource")
  property var detectedLayer: null
  property string lastUniteObs: ""
  property string lastLithologie: ""
  property string lastFacies: ""
  property string gpsText: "GPS non vérifié"

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(clinoButton)
    mainWindow.displayToast("QField Clino v0.3 chargé")
  }

  function fieldNames(layer) {
    if (!layer || !layer.fields) return []
    try { return layer.fields.names } catch (e) { return [] }
  }

  function scoreLayer(layer) {
    const n = fieldNames(layer)
    let s = 0
    const wanted = ["azimut","pendage","strike","unite_obs","unite","lithologie","facies","note"]
    for (let i=0;i<wanted.length;i++) if (n.indexOf(wanted[i]) >= 0) s++
    const name=(layer.name||"").toLowerCase()
    if (name.indexOf("pendage")>=0 || name.indexOf("clino")>=0) s+=2
    return s
  }

  function findLayer() {
    let layers=[]
    try { layers=mapCanvas.mapSettings.layers } catch(e) { return null }
    let best=null, bestScore=-1
    for (let i=0;i<layers.length;i++) {
      const l=layers[i]
      if (!l || !l.fields) continue
      const s=scoreLayer(l)
      if (s>bestScore) { best=l; bestScore=s }
    }
    detectedLayer=best
    return best
  }

  function updateGps() {
    if (!positionSource || !positionSource.active) {
      gpsText="GPS inactif — active le positionnement QField"
      return false
    }
    const info=positionSource.positionInformation
    if (!info.longitudeValid || !info.latitudeValid) {
      gpsText="GPS actif, mais pas encore de position valide"
      return false
    }
    gpsText="GPS : " + Number(info.latitude).toFixed(6) + ", " + Number(info.longitude).toFixed(6)
    return true
  }

  function prepareForm() {
    findLayer()
    updateGps()
    uniteObs.text=lastUniteObs
    lithologie.text=lastLithologie
    facies.text=lastFacies
    uniteCarte.text=""
  }

  function saveLastValues() {
    lastUniteObs=uniteObs.text
    lastLithologie=lithologie.text
    lastFacies=facies.text
    mainWindow.displayToast("Valeurs terrain mémorisées. Écriture GeoPackage à l'étape suivante.")
    clinoDialog.close()
  }

  QfToolButton {
    id: clinoButton
    iconSource: Theme.getThemeVectorIcon("ic_explore_white_24dp")
    iconColor: Theme.toolButtonColor
    bgcolor: Theme.toolButtonBackgroundColor
    round: true
    onClicked: { prepareForm(); clinoDialog.open() }
  }

  Dialog {
    id: clinoDialog
    parent: mainWindow.contentItem
    modal: true
    title: "QField Clino v0.3 — Nouveau pendage"
    width: Math.min(parent.width-20,500)
    height: Math.min(parent.height-30,760)
    x:(parent.width-width)/2
    y:(parent.height-height)/2

    ScrollView {
      anchors.fill: parent
      contentWidth: availableWidth
      ColumnLayout {
        width: parent.width
        spacing: 8

        Label { Layout.fillWidth:true; wrapMode:Text.WordWrap; text: detectedLayer ? "Couche : "+detectedLayer.name : "Couche pendages non détectée" }
        Label { Layout.fillWidth:true; wrapMode:Text.WordWrap; text:gpsText }
        Button { Layout.fillWidth:true; text:"Actualiser GPS"; onClicked:updateGps() }

        Label { text:"Azimut (°)" }
        TextField { id:azimut; Layout.fillWidth:true; inputMethodHints:Qt.ImhFormattedNumbersOnly; placeholderText:"ex. 135" }
        Label { text:"Pendage (°)" }
        TextField { id:pendage; Layout.fillWidth:true; inputMethodHints:Qt.ImhFormattedNumbersOnly; placeholderText:"ex. 42" }
        Label { text:"Strike (°)" }
        TextField { id:strike; Layout.fillWidth:true; inputMethodHints:Qt.ImhFormattedNumbersOnly; placeholderText:"facultatif pour ce test" }

        Label { text:"Unité carte" }
        TextField { id:uniteCarte; Layout.fillWidth:true; readOnly:true; placeholderText:"automatique avec carte géologique (prochaine étape)" }
        Label { text:"Unité observée" }
        TextField { id:uniteObs; Layout.fillWidth:true; placeholderText:"ex. Valanginien" }
        Label { text:"Lithologie" }
        TextField { id:lithologie; Layout.fillWidth:true; placeholderText:"ex. Calcaire" }
        Label { text:"Faciès" }
        TextField { id:facies; Layout.fillWidth:true; placeholderText:"ex. bioclastique" }
        Label { text:"Note" }
        TextArea { id:note; Layout.fillWidth:true; Layout.preferredHeight:80; wrapMode:TextEdit.Wrap; placeholderText:"Observation libre" }

        Button {
          Layout.fillWidth:true
          text:"MÉMORISER CE PENDAGE (test V0.3)"
          enabled: detectedLayer !== null
          onClicked:saveLastValues()
        }
        Label {
          Layout.fillWidth:true; wrapMode:Text.WordWrap
          text:"V0.3 valide le formulaire, le GPS et la mémoire des valeurs. Elle n'écrit pas encore dans le GeoPackage : on sécurise cette étape avant la V0.4."
        }
      }
    }
  }
}
