import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import Theme

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var dashBoard: iface.findItemByObjectName("dashBoard")

  Component.onCompleted: {
    iface.addItemToPluginsToolbar(clinoButton)
    mainWindow.displayToast("QField Clino v0.1 chargé")
  }

  QfToolButton {
    id: clinoButton
    iconSource: Theme.getThemeVectorIcon("ic_explore_white_24dp")
    iconColor: Theme.toolButtonColor
    bgcolor: Theme.toolButtonBackgroundColor
    round: true

    onClicked: clinoDialog.open()
  }

  Dialog {
    id: clinoDialog
    parent: mainWindow.contentItem
    modal: true
    title: "QField Clino v0.1"
    standardButtons: Dialog.Ok
    width: Math.min(parent.width - 32, 420)
    x: (parent.width - width) / 2
    y: Math.max(16, (parent.height - height) / 2)

    ColumnLayout {
      width: parent.width
      spacing: 12

      Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Premier test du plugin général."
      }

      Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: {
          if (!dashBoard)
            return "Couche active : non détectée"
          if (!dashBoard.activeLayer)
            return "Couche active : aucune"
          return "Couche active : " + dashBoard.activeLayer.name
        }
      }

      Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Étape suivante : détection automatique de la couche Pendages, de ses champs et de son SCR."
      }
    }
  }
}
