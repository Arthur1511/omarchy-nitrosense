import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live Acer Nitro fan/thermal widget: bar pill shows CPU temperature and fan
// speed, the popup shows all sensor readings and the four fan modes
// (auto/quiet/balance/game). Sampling and EC writes live in `nitro-ec`,
// driven by this widget's Timer — no daemon, no root at runtime.
//
// Root is a plain BarWidget with a self-managed PopupCard (the same shape as
// the built-in Tray widget): bar buttons that summon a popup cannot use the
// module `Panel` base on this shell build, so open/close lives on the widget.
BarWidget {
  id: root
  moduleName: "io.github.bobster05.nitrosense"

  readonly property string helperScript: String(Qt.resolvedUrl("nitro-ec")).replace("file://", "")
  readonly property string setupScript: String(Qt.resolvedUrl("setup.sh")).replace("file://", "")

  property bool opened: false
  function open() { root.opened = true }
  function close() { root.opened = false }
  function toggle() { root.opened ? root.close() : root.open() }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: Color.urgent
  readonly property color warn: Qt.lighter(Color.urgent, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var stats: ({})
  property string activeMode: ""
  readonly property bool hasStats: stats && stats.cpuTemp !== undefined
  readonly property bool hasEc: hasStats && stats.ec === true
  readonly property bool anyHot: stats && (isHot(stats.cpuTemp, 90) || isHot(stats.gpuTemp, 95) || isHot(stats.sysTemp, 85))

  function isHot(v, limit) { return v !== null && v !== undefined && Number(v) >= limit }
  function tempColor(v, warnAt, critAt) {
    if (v === null || v === undefined) return root.foreground
    var n = Number(v)
    if (n >= critAt) return root.urgent
    if (n >= warnAt) return root.warn
    return root.foreground
  }
  function fmtTemp(v) { return (v === null || v === undefined || isNaN(Number(v))) ? "—" : Math.round(Number(v)) + "°C" }
  function fmtRpm(v) { return (v === null || v === undefined || isNaN(Number(v))) ? "—" : Math.round(Number(v)) + " RPM" }

  function profile() {
    var n = stats.nitroMode
    if (n === 0) return "quiet"
    if (n === 1) return "balance"
    if (n === 4) return "game"
    return "auto"
  }
  function inferMode() {
    var n = stats.nitroMode
    if (n === 0) return "quiet"
    if (n === 4) return "game"
    return "auto"
  }
  function profileText() {
    var n = stats.nitroMode
    if (n === 0) return "Тихий"
    if (n === 1) return "Баланс"
    if (n === 4) return "Игра"
    return "Авто"
  }
  function fansText() {
    var c = stats.cpuMode
    var g = stats.gpuMode
    if (c === 0x04 && g === 0x10) return "Авто"
    if (c === 0x08 || g === 0x20) return "Турбо"
    return "Ручной"
  }

  readonly property var modes: [
    { key: "auto", label: "Авто", hint: "Вентиляторы на автоматике" },
    { key: "quiet", label: "Тихий", hint: "Тихий режим, вентиляторы на автом. подстройке" },
    { key: "balance", label: "Баланс", hint: "Сбалансированный режим, вентиляторы на автомате" },
    { key: "game", label: "Игра", hint: "Максимальная производительность, вентиляторы на максимум" }
  ]

  readonly property string barText: root.hasStats
    ? root.fmtTemp(stats.cpuTemp) + (stats.cpuFanRpm ? " · " + Math.round(stats.cpuFanRpm) : "")
    : "Nitro"
  readonly property string tooltip: root.hasStats
    ? ("CPU " + root.fmtTemp(stats.cpuTemp) + "  ·  " + root.fmtRpm(stats.cpuFanRpm)
       + "\nПрофиль: " + root.profileText() + " · Вентилятор: " + root.fansText()
       + (root.hasEc ? "" : "\nEC недоступен — выполните setup.sh (sudo)"))
    : "NitroSense\nЛКМ: настройки вентилятора"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }
  function applyMode(key) {
    if (!root.hasEc) return
    root.activeMode = key
    var command = [root.helperScript, "set", key]
    setProc.command = command
    setProc.running = true
  }
  function cycleModes(delta) {
    var start = root.modes.indexOf(root.modes.filter(m => m.key === root.profile())[0])
    if (start < 0) start = 0
    var step = delta > 0 ? 1 : -1
    var next = root.modes[(start + step + root.modes.length) % root.modes.length]
    root.applyMode(next.key)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    id: poller
    interval: root.opened ? 1000 : 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.helperScript, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || ""))
          if (parsed && typeof parsed === "object") {
            root.stats = parsed
            if (root.activeMode === "" && parsed.ec === true) root.activeMode = root.inferMode()
            console.log("nitro stats", JSON.stringify(root.stats))
          }
        } catch (e) { /* keep last good snapshot */ }
      }
    }
  }

  Process {
    id: setProc
    command: [root.helperScript, "set", "auto"]
    onExited: Qt.callLater(function() {
      if (!statusProc.running) statusProc.running = true
    })
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    tooltipText: root.tooltip
    active: root.anyHot
    useActiveColor: root.anyHot
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
      else if (mouseButton === Qt.RightButton && root.hasEc) root.cycleModes(1)
    }
    onWheelMoved: function(delta) { if (root.hasEc) root.cycleModes(delta) }
  }

  component StatRow: Item {
    property string label: ""
    property string value: ""
    property color valueColor: root.foreground

    width: parent ? parent.width : implicitWidth
    height: valueText.implicitHeight

    Text {
      id: valueText
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: parent.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.left: parent.left
      anchors.right: valueText.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.spacing.xs
      elide: Text.ElideRight
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(320))
    contentHeight: fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.spacing.md

      Text {
        text: "Nitro Sense"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        visible: root.hasEc
        text: "Профиль: " + root.profileText() + " · Вентилятор: " + root.fansText()
        color: Qt.darker(root.foreground, 1.25)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.hasStats && !root.hasEc
        text: "EC недоступен — для управления вентилятором\nвыполните: sudo " + root.setupScript
        color: root.warn
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          foreground: root.foreground
          fontFamily: root.fontFamily
          text: "ТЕМПЕРАТУРА"
        }

        StatRow { label: "CPU"; value: root.fmtTemp(root.stats ? root.stats.cpuTemp : null); valueColor: root.tempColor(root.stats ? root.stats.cpuTemp : null, 80, 90) }
        StatRow { label: "GPU"; value: root.fmtTemp(root.stats ? root.stats.gpuTemp : null); valueColor: root.tempColor(root.stats ? root.stats.gpuTemp : null, 85, 95) }
        StatRow { label: "Система"; value: root.fmtTemp(root.stats ? root.stats.sysTemp : null); valueColor: root.tempColor(root.stats ? root.stats.sysTemp : null, 70, 85) }
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          foreground: root.foreground
          fontFamily: root.fontFamily
          text: "ВЕНТИЛЯТОРЫ"
        }

        StatRow { label: "CPU"; value: root.fmtRpm(root.stats ? root.stats.cpuFanRpm : null) }
        StatRow { label: "GPU"; value: root.fmtRpm(root.stats ? root.stats.gpuFanRpm : null) }

      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader {
          foreground: root.foreground
          fontFamily: root.fontFamily
          text: "РЕЖИМ ВЕНТИЛЯТОРА"
        }

        Grid {
          id: modeGrid
          width: parent.width
          spacing: Style.spacing.sm
          columns: 2

          Repeater {
            model: root.modes

            Button {
              width: (modeGrid.width - modeGrid.spacing) / 2
              text: modelData.label
              tooltipText: modelData.hint
              foreground: root.foreground
              selected: root.hasEc && root.activeMode === modelData.key
              opacity: root.hasEc ? 1.0 : 0.45
              onClicked: root.applyMode(modelData.key)
            }
          }

        }
      }
    }
  }
}