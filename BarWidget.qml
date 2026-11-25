import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The switch for hardcore mode: a flame, dim while off and lit while on.
// Click turns it on and off; right click opens a menu with the mode and a
// switch for each part of it.
BarWidget {
  id: root
  moduleName: "io.github.tanevanwifferen.hardcore"

  readonly property var hardcore: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.tanevanwifferen.hardcore") : null
  readonly property bool on: hardcore ? hardcore.on === true : false
  readonly property string modeName: hardcore && hardcore.mode ? strings.t("mode." + hardcore.mode.name) : ""
  // Always in view, unlike the indicators that hide while inactive.
  readonly property bool revealInactiveIndicators: true

  property bool popupOpen: false
  function close() { popupOpen = false }

  // The parts that can be switched off one by one, as the service names them.
  readonly property var parts: ["shaking", "sparks", "edges", "counter", "sound"]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  BarIndicator {
    id: button
    anchors.centerIn: parent
    bar: root.bar
    indicatorHost: root
    active: root.on
    activeText: "󰈸"
    activeTooltipText: root.popupOpen ? "" : strings.t("tooltip.on").arg(root.modeName)
    inactiveTooltipText: root.popupOpen ? "" : strings.t("tooltip.off").arg(root.modeName)
    onPressed: function(button) {
      if (!root.hardcore) return
      if (button === Qt.RightButton) root.popupOpen = !root.popupOpen
      else root.hardcore.toggle()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      Toggle {
        width: parent.width
        label: strings.t("menu.on")
        description: strings.t("menu.on.description")
        checked: root.on
        onClicked: if (root.hardcore) root.hardcore.toggle()
      }

      ButtonGroup {
        options: root.hardcore ? root.hardcore.modes.map(function(mode) {
          return { value: mode.name, label: strings.t("mode." + mode.name) }
        }) : []
        value: root.hardcore && root.hardcore.mode ? root.hardcore.mode.name : ""
        focusable: false
        onChanged: function(value) { if (root.hardcore) root.hardcore.setMode(value) }
      }

      Repeater {
        model: root.parts

        Toggle {
          required property string modelData
          width: column.width
          label: strings.t("menu." + modelData)
          description: strings.t("menu." + modelData + ".description")
          checked: root.hardcore ? root.hardcore[modelData] === true : false
          onClicked: if (root.hardcore) root.hardcore[modelData] = !root.hardcore[modelData]
        }
      }
    }
  }
}
