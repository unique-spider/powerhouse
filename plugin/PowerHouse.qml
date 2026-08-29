import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Power House — governed laptop control in one theme-adaptive bar panel.
//   Keys · OC · Fan · Power · Guard · Batt · Sys · Gov
// State: one `powerhouse status` JSON. Privileged tweaks go through
// `pkexec powerhouse-apply` (polkit password every time) and are clamped by the
// root governor, which also enforces the caps every 3 s regardless of this UI.
Panel {
  id: root
  moduleName: "uniquespider.powerhouse"
  ipcTarget: "uniquespider.powerhouse"
  manageIpc: false

  readonly property string ctl: (Quickshell.env("HOME") || "") + "/.local/bin/powerhouse"

  // ---------------------------------------------------------------- state
  property var fan: ({})
  property var kbd: ({})
  property var gpu: ({})
  property var power: ({})
  property var batt: ({})
  property var privacy: ({})
  property var clam: ({})
  property var guard: ({})
  property var gov: ({})
  property var keys: ({})
  property var ai: ({})
  property var insight: ({})
  property string tab: "keys"
  property bool busy: false
  property string lastResult: ""
  property int manualLevel: 8
  property int cpuAvg: 0
  property var cpuHist: []
  property int wantGpc: -1
  property int wantMem: -1
  property int wantPl1: -1
  property int wantPl2: -1
  property string excludeDraft: ""
  property string aiOut: ""

  readonly property var omatop: bar && bar.shell ? bar.shell.serviceFor("ryanyogan.omatop") : null

  // ---------------------------------------------------------------- design tokens
  readonly property color cGood: root.bar ? root.bar.foreground : Color.foreground
  readonly property color cWarn: "#d99a2b"
  readonly property color cBad: root.bar ? root.bar.urgent : Color.urgent
  readonly property color cInfo: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.6) : Color.foreground
  readonly property color cMute: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.foreground
  readonly property color cFill: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12) : "#333"
  readonly property color cInsight: "#5bbd6a"
  function lvlColor(l) { return l === "bad" ? cBad : l === "warn" ? cWarn : l === "good" ? cInsight : cInfo }

  readonly property var tabs: [
    { id: "keys",     icon: "󰌌", label: "Keys" },
    { id: "oc",       icon: "󰢮", label: "OC" },
    { id: "fans",     icon: "󰈐", label: "Fan" },
    { id: "power",    icon: "󱐋", label: "Power" },
    { id: "guard",    icon: "󰒃", label: "Guard" },
    { id: "battery",  icon: "󰁹", label: "Batt" },
    { id: "system",   icon: "󰍛", label: "Sys" },
    { id: "gov",      icon: "󰚩", label: "Gov" }
  ]

  // ---- governor
  readonly property bool govOnline: gov.online === true
  readonly property var limits: gov.limits || {}
  readonly property var gsample: gov.sample || {}
  readonly property var ggpu: gsample.gpu || {}
  readonly property var gcpu: gsample.cpu || {}
  readonly property var gec: gov.ec || {}
  readonly property var gkbd: gov.kbd || {}
  readonly property var incidents: gov.incidents || []
  readonly property var crashLocked: limits.crash_locked || ({})
  readonly property int lockGpc: crashLocked.gpc !== undefined ? Number(crashLocked.gpc) : -1
  readonly property int lockMem: crashLocked.mem !== undefined ? Number(crashLocked.mem) : -1
  property var timeline: []
  readonly property int gpcMax: Number(limits.gpc_max !== undefined ? limits.gpc_max : 100)
  readonly property int memMax: Number(limits.mem_max !== undefined ? limits.mem_max : 300)
  readonly property int pl1Max: Number(limits.pl1_max !== undefined ? limits.pl1_max : 45)
  readonly property int pl2Max: Number(limits.pl2_max !== undefined ? limits.pl2_max : 115)
  readonly property int curGpc: Number(ggpu.gpc !== undefined ? ggpu.gpc : (gpu.gpcOffset || 0))
  readonly property int curMem: Number(ggpu.mem !== undefined ? ggpu.mem : (gpu.memOffset || 0))
  readonly property int curPl1: Number(gcpu.pl1 !== undefined ? gcpu.pl1 : (power.cpuPl1 || 45))
  readonly property int curPl2: Number(gcpu.pl2 !== undefined ? gcpu.pl2 : (power.cpuPl2 || 115))
  readonly property bool stockNow: curGpc === 0 && curMem === 0 && curPl1 === 45 && curPl2 === 115
  readonly property string aiFlag: String(gov.ai_review || "").trim()
  readonly property bool aiReview: aiFlag === "opus"          // only a real crash asks for the Opus pass
  readonly property bool aiNudge: aiFlag === "sonnet"         // an enforcement/thermal event asked for a routine review
  readonly property bool ecTripped: gec.disabled === true
  readonly property string thermal: String(gov.thermal || "normal")
  readonly property bool thermalActive: thermal !== "normal"

  // ---- fans
  readonly property string fanModeRaw: String(fan.modeRaw || "…")
  readonly property bool fanOnline: fan.online === true
  readonly property bool maxed: String(fan.mode || "") === "max"
  readonly property bool manual: fanModeRaw === "MANUAL"
  readonly property int rpm1: Number(fan.rpm1 || 0)
  readonly property int rpm2: Number(fan.rpm2 || 0)
  readonly property int cpuNow: Number(fan.cpu || 0)
  readonly property string gpuTempFan: String(fan.gpu || "—")
  readonly property string activeFanMode: maxed ? "max" : fanModeRaw === "MANUAL" ? "manual" : fanModeRaw === "BETTER_AUTO" ? "better_auto" : "auto"
  readonly property var fanModes: [
    { id: "auto",        args: ["fan", "plainauto"], icon: "󰾆", label: "Auto" },
    { id: "better_auto", args: ["fan", "auto"],      icon: "󱠇", label: "Better" },
    { id: "manual",      args: null,                 icon: "󰑬", label: "Manual" },
    { id: "max",         args: ["fan", "max"],       icon: "󰈐", label: "Max" }
  ]

  // ---- keyboard
  readonly property string audio: String(kbd.audio || "off")
  readonly property bool audioOn: audio === "beat" || audio === "smooth"
  readonly property int kbdLevel: Number(kbd.kbd || 0)
  readonly property bool kbdTesting: String(kbd.test || "off") === "on"
  readonly property var presets: kbd.presets && kbd.presets.length ? kbd.presets : ["Kick", "Club", "Subtle", "Vibe", "Mellow", "Intense"]
  readonly property var excluded: keys.excluded || []
  readonly property var streams: (keys.routing && keys.routing.streams) ? keys.routing.streams : []
  function streamKey(s) { var i = s.ident || {}; return i.binary || i.app || i.node || "" }
  function isExcluded(s) { var k = root.streamKey(s); return root.excluded.indexOf(k) >= 0 }

  // ---- privacy / battery
  readonly property bool helperInstalled: privacy.helper === true
  readonly property string camState: String(privacy.cam || "?")
  readonly property string micState: String(privacy.micUser || privacy.mic || "?")
  readonly property bool capOn: batt.capOn === true
  readonly property bool capLive: !!(power.battery && power.battery.chargeCap === true)
  readonly property int batPct: Number((power.battery && power.battery.pct) || batt.capacity || 0)

  readonly property string statusLabel: (root.govOnline ? (root.stockNow ? "STOCK" : "TUNED") : "GOV OFFLINE")
    + " · " + (root.maxed ? "FANS MAX" : root.fanModeRaw === "BETTER_AUTO" ? "BETTER AUTO" : root.fanModeRaw)
    + (root.aiReview ? " · CRASH REVIEW PENDING" : root.aiNudge ? " · REVIEW QUEUED" : "") + (root.thermalActive ? " · THERMAL " + root.thermal.toUpperCase() : "")
  readonly property string labelText: "󰚩 " + Math.max(rpm1, rpm2) + (maxed ? " MAX" : "") + "  " + cpuAvg + "°"

  // ---------------------------------------------------------------- plumbing
  function refresh() { if (!statusProc.running) statusProc.running = true }
  function run(args) {
    if (actionProc.running) return
    actionProc.command = [root.ctl].concat(args)
    root.busy = true
    actionProc.running = true
  }
  function loadInsights() { if (!insightsProc.running) insightsProc.running = true }
  function runAi(args) { if (aiProc.running) return; root.aiOut = "running " + args.join(" ") + "…"; aiProc.command = [root.ctl, "ai"].concat(args); aiProc.running = true }

  function applyStatus(text) {
    try {
      var d = JSON.parse(String(text || "{}"))
      root.fan = d.fan || {}; root.kbd = d.kbd || {}; root.gpu = d.gpu || {}
      root.power = d.power || {}; root.batt = d.battery || {}; root.privacy = d.privacy || {}
      root.clam = d.clamshell || {}; root.guard = d.guard || {}
      root.gov = d.governor || {}; root.keys = d.keys || {}; root.ai = d.ai || {}; root.timeline = d.timeline || []
      var h = root.cpuHist.slice(); h.push(Number(root.fan.cpu || 0)); if (h.length > 5) h.shift()
      root.cpuHist = h
      root.cpuAvg = Math.round(h.reduce(function(a, b) { return a + b }, 0) / h.length)
    } catch (e) {}
  }
  function fmtMB(mb) { return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : mb + " MB" }
  function timeAgo(epochSec) {
    var s = Math.max(0, Math.round(Date.now() / 1000 - Number(epochSec)))
    if (s < 60) return s + "s ago"
    if (s < 3600) return Math.round(s / 60) + "m ago"
    if (s < 86400) return Math.round(s / 3600) + "h ago"
    return Math.round(s / 86400) + "d ago"
  }
  function pct(x) { return Math.round(Number(x) || 0) + "%" }
  function fmtT(epochSec) { return new Date(Number(epochSec) * 1000).toLocaleString(Qt.locale(), "MMM d HH:mm") }
  function fmtTS(epochSec) { return new Date(Number(epochSec) * 1000).toLocaleString(Qt.locale(), "ddd d MMM HH:mm:ss") }
  function signed(n) { return (n > 0 ? "+" : "") + n }

  IpcHandler {
    target: "uniquespider.powerhouse"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function tab(name: string): void { root.tab = name; root.open() }
    function stock() { root.run(["tweak", "stock"]) }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: [root.ctl, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }
  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.lastResult = String(text || "").trim().split("\n").pop().slice(0, 90) }
    onExited: { root.busy = false; root.refresh() }
  }
  Process {
    id: insightsProc
    command: [root.ctl, "guard", "insights", "24"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.insight = JSON.parse(String(text || "{}")) } catch (e) {} } }
  }
  Process {
    id: aiProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.aiOut = String(text || "").trim() }
    onExited: root.refresh()
  }

  Timer { interval: root.opened ? 1500 : 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  onOpenedChanged: if (opened) { root.lastResult = ""; refresh() }

  // ---------------------------------------------------------------- bar button
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.labelText
    foreground: (root.aiReview || root.ecTripped || !root.govOnline) ? root.cWarn : root.maxed ? (root.bar ? root.bar.urgent : Color.urgent) : Color.bar.text
    activeColor: Color.bar.active
    active: root.maxed || root.opened
    horizontalMargin: 8.5
    verticalPadding: 6
    tooltipText: "Power House — " + root.statusLabel + "\n" + root.rpm1 + " / " + root.rpm2 + " rpm · CPU " + root.cpuAvg + "°C · GPU " + root.gpuTempFan + "°C"
      + "\nleft-click: panel · right-click: MAX ↔ Better Auto"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run(["fan", root.maxed ? "auto" : "max"])
      else if (b === Qt.LeftButton) root.toggle()
    }
  }

  // ---------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(580))
    contentHeight: panel.fittedContentHeight(fixedCol.implicitHeight + Style.space(14) + pagesCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) { flick.scrollBy(dy * Style.space(80)); return }
        if (dx === 0) return
        var ids = root.tabs.map(function(t) { return t.id })
        root.tab = ids[(ids.indexOf(root.tab) + dx + ids.length) % ids.length]
      }

      // Header + tabs stay fixed; the page below scrolls when it is taller than the screen allows.
      Column {
        id: fixedCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTemp.implicitHeight)
          Text {
            id: heroIcon
            text: "󰚩"; color: root.govOnline ? root.bar.foreground : root.cWarn
            font.family: root.bar.fontFamily; font.pixelSize: Style.font.displayLarge
            SequentialAnimation on opacity { running: root.busy; loops: Animation.Infinite; alwaysRunToEnd: true
              NumberAnimation { to: 0.35; duration: 420; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutSine } }
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            id: heroLabels
            anchors.left: heroIcon.right; anchors.leftMargin: Style.space(14)
            anchors.right: heroTemp.left; anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Title { text: "Power House" }
            Caption { text: root.busy ? "APPLYING…" : (root.lastResult !== "" ? root.lastResult.toUpperCase() : root.statusLabel)
                      color: root.aiReview || !root.govOnline ? root.cWarn : root.cMute }
          }
          Column {
            id: heroTemp
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
              text: root.cpuAvg + "°"
              color: root.cpuAvg >= 90 ? root.cBad : root.bar.foreground
              font.family: root.bar.fontFamily; font.pixelSize: Style.font.displayLarge; font.bold: true
              anchors.right: parent.right
            }
          }
        }

        // ---------- Tabs ----------
        Item {
          id: tabRow
          width: parent.width
          implicitHeight: tabsRow.implicitHeight + Style.space(4)
          readonly property real gap: Style.space(4)
          readonly property real cellWidth: (width - gap * (root.tabs.length - 1)) / root.tabs.length
          readonly property int idx: Math.max(0, root.tabs.map(function(t) { return t.id }).indexOf(root.tab))
          Rectangle {
            x: tabRow.idx * (tabRow.cellWidth + tabRow.gap); y: 0
            width: tabRow.cellWidth; height: tabsRow.implicitHeight
            radius: Style.space(8); color: root.cFill
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
          }
          Row {
            id: tabsRow
            spacing: tabRow.gap
            Repeater {
              model: root.tabs
              Item {
                id: tabItem
                required property var modelData
                readonly property bool on: root.tab === modelData.id
                width: tabRow.cellWidth; implicitHeight: tabCol.implicitHeight + Style.space(14)
                Column {
                  id: tabCol
                  anchors.centerIn: parent; spacing: Style.space(3)
                  Text { text: tabItem.modelData.icon; anchors.horizontalCenter: parent.horizontalCenter
                    color: tabItem.on ? root.bar.foreground : (tabItem.modelData.id === "gov" && root.aiReview ? root.cWarn : root.cMute)
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.iconLarge
                    scale: tabItem.on ? 1.15 : 1.0
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } } }
                  Text { text: tabItem.modelData.label; anchors.horizontalCenter: parent.horizontalCenter
                    color: tabItem.on ? root.bar.foreground : root.cMute
                    font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1
                    Behavior on color { ColorAnimation { duration: 200 } } }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                  onClicked: { root.tab = tabItem.modelData.id; flick.contentY = 0; if (tabItem.modelData.id === "guard") root.loadInsights() } }
              }
            }
          }
          Rectangle {
            anchors.bottom: parent.bottom
            x: tabRow.idx * (tabRow.cellWidth + tabRow.gap) + tabRow.cellWidth * 0.3
            width: tabRow.cellWidth * 0.4; height: Style.space(2); radius: 1; color: root.bar.foreground
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
          }
        }
        PanelSeparator { foreground: root.bar.foreground }
      }

      Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: fixedCol.bottom
        anchors.topMargin: Style.space(14)
        // The content item is not height-capped by the shell; derive the visible height from the panel's real contentHeight.
        height: Math.max(Style.space(140), panel.contentHeight - (Number(panel.verticalContentInset) || 0) - fixedCol.implicitHeight - Style.space(14))
        contentWidth: width
        contentHeight: pagesCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        Connections { target: root; function onTabChanged() { flick.contentY = 0 } }
        readonly property bool scrollable: contentHeight > height + 1
        function scrollBy(px) { contentY = Math.max(0, Math.min(contentHeight - height, contentY + px)) }

      Column {
        id: pagesCol
        width: flick.width - (flick.contentHeight > flick.height ? Style.space(12) : 0)
        spacing: Style.space(14)

        // =========================================================== KEYS
        Page {
          tabId: "keys"; spacing: Style.space(12)
          Row {
            width: parent.width; spacing: Style.space(8)
            Column {
              width: parent.width - kStart.width - parent.spacing; spacing: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              Title { text: "Audio-reactive backlight" }
              Caption { text: !root.govOnline ? "GOVERNOR OFFLINE — KEYS DISABLED" : root.ecTripped ? "EC BUDGET TRIPPED — RESET IN GOV TAB"
                          : root.audioOn ? "RUNNING · " + root.audio.toUpperCase() + " · " + String(root.kbd.preset || "").toUpperCase() : (root.kbdLevel > 0 ? "STEADY ON" : "OFF")
                        color: (!root.govOnline || root.ecTripped) ? root.cWarn : root.cMute }
            }
            ToggleSwitch {
              id: kStart
              anchors.verticalCenter: parent.verticalCenter
              checked: root.audioOn; busy: root.busy; enabled: root.govOnline && !root.ecTripped
              foreground: root.bar.foreground; accent: root.bar.foreground
              onToggled: root.run(["keys", "audio", root.audioOn ? "off" : "on"])
            }
          }
          Tiles {
            Tile { icon: "󰓅"; label: "EC WRITES/S"; value: String(Number(root.gec.rate || 0)); unit: "/ " + Number(root.limits.kbd_writes_per_s_max || 400); hot: root.ecTripped }
            Tile { icon: "󰑓"; label: "PWM"; value: String(Number(root.limits.kbd_pwm_hz || 125)); unit: "Hz" }
            Tile { icon: "󰌌"; label: "DUTY"; value: String(Number(root.gkbd.duty || 0)); unit: "%" }
          }
          Note { visible: root.limits.kbd_audio_allowed === false; color: root.cWarn; opacity: 1
            text: "Audio-reactive dimming is currently DISABLED in the governor limits (kbd_audio_allowed=false — set by " + String(root.limits.source || "?") + "). Keys hold steady instead. Restore with the password: Gov tab → Restore defaults." }
          Note { text: "All keyboard writes go through the governor — one process, one lock, register 0x1805 only. The budget above is the keys' power allowance: exceed it and the arbiter trips instead of the laptop crashing. Lower it any time; raising it asks for your password." }
          Section { text: "KEYS BUDGET" }
          Column { width: parent.width; spacing: Style.space(6)
            Pair { label: "PWM frequency"; value: Number(root.limits.kbd_pwm_hz || 125) + " Hz" }
            PanelSlider { width: parent.width; bar: root.bar; minimum: 20; maximum: 250; step: 5; integer: true; value: Number(root.limits.kbd_pwm_hz || 125)
              onReleased: function(v) { root.run(["keys", "budget", String(Math.round(v)), String(Number(root.limits.kbd_writes_per_s_max || 400))]) } }
            Pair { label: "Max EC writes per second"; value: String(Number(root.limits.kbd_writes_per_s_max || 400)) }
            PanelSlider { width: parent.width; bar: root.bar; minimum: 20; maximum: 600; step: 10; integer: true; value: Number(root.limits.kbd_writes_per_s_max || 400)
              onReleased: function(v) { root.run(["keys", "budget", String(Number(root.limits.kbd_pwm_hz || 125)), String(Math.round(v))]) } }
          }
          Section { text: "APPS THAT MUST NOT DRIVE THE KEYS" }
          Note { text: "Excluded apps still play through your speakers/headphones — they are just routed around the sink the keys listen to." }
          Column {
            width: parent.width; spacing: Style.space(4)
            Repeater {
              model: root.streams
              Row {
                required property var modelData
                width: parent.width; spacing: Style.space(8)
                readonly property string key: root.streamKey(modelData)
                readonly property bool ex: root.isExcluded(modelData)
                Text { text: ex ? "󰝟" : "󰕾"; color: ex ? root.cWarn : root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; anchors.verticalCenter: parent.verticalCenter }
                Column { width: parent.width - parent.children[0].implicitWidth - exBtn.width - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
                  Text { text: String(modelData.label || key); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; width: parent.width }
                  Caption { text: (ex ? "BYPASSES KEYS" : "DRIVES KEYS") + " · " + String(modelData.sink || "").replace("alsa_output.", "").slice(0, 40) } }
                Button { id: exBtn; anchors.verticalCenter: parent.verticalCenter; text: ex ? "Allow" : "Exclude"; fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true; active: ex; enabled: key !== ""
                  onClicked: root.run(["keys", "exclude", ex ? "remove" : "add", key]) }
              }
            }
            Note { visible: !root.streams.length; text: "No apps are playing audio right now." }
          }
          Row {
            width: parent.width; spacing: Style.space(6)
            Rectangle { width: parent.width - exAdd.width - parent.spacing; height: exAdd.height; radius: Style.space(6); color: root.cFill
              TextInput { id: exInput; anchors.fill: parent; anchors.margins: Style.space(8); verticalAlignment: TextInput.AlignVCenter
                color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; clip: true
                onTextChanged: root.excludeDraft = text; onAccepted: exAdd.clicked() }
              Text { visible: exInput.text === ""; anchors.fill: parent; anchors.margins: Style.space(8); verticalAlignment: Text.AlignVCenter
                text: "app name (e.g. discord, spotify, chromium)"; color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body } }
            Button { id: exAdd; text: "Add exclusion"; fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true
              enabled: root.excludeDraft.trim() !== ""
              onClicked: { if (root.excludeDraft.trim() !== "") { root.run(["keys", "exclude", "add", root.excludeDraft.trim()]); exInput.text = "" } } }
          }
          Row { width: parent.width; spacing: Style.space(6)
            Repeater { model: root.excluded
              Button { required property var modelData; text: String(modelData) + "  ✕"; fontSize: Style.font.caption; foreground: root.cWarn; fontFamily: root.bar.fontFamily; bordered: true
                onClicked: root.run(["keys", "exclude", "remove", String(modelData)]) } } }
          Section { text: "PRESETS" }
          Grid {
            id: presetGrid
            width: parent.width; columns: 3; columnSpacing: Style.space(6); rowSpacing: Style.space(6)
            readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns
            Repeater {
              model: root.presets
              Button {
                required property var modelData
                width: presetGrid.cellWidth; text: String(modelData); fontSize: Style.font.bodySmall
                foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true
                active: String(root.kbd.preset || "") === String(modelData)
                onClicked: root.run(["keys", "audio", "preset", String(modelData)])
              }
            }
          }
          ButtonRow {
            model: [ { id: "beat", icon: "󰎈", label: "Beat (kicks)" }, { id: "smooth", icon: "󰽰", label: "Smooth (gate)" } ]
            activeId: String(root.kbd.mode || "beat")
            onPicked: function(m) { root.run(root.audioOn ? ["keys", "audio", "set", "mode", m.id] : ["keys", "audio", "start", m.id]) }
          }
          Column { width: parent.width; spacing: Style.space(6)
            Pair { label: "Gain (sensitivity)"; value: "×" + Number(root.kbd.gain || 1.4).toFixed(1) }
            PanelSlider { width: parent.width; bar: root.bar; minimum: 0.3; maximum: 4.0; step: 0.1; value: Number(root.kbd.gain || 1.4)
              onReleased: function(v) { root.run(["keys", "audio", "set", "gain", (Math.round(v * 10) / 10).toString()]) } } }
          Section { text: "STEADY BACKLIGHT" }
          Row {
            width: parent.width; spacing: Style.space(8)
            Column {
              width: parent.width - kSteady.width - parent.spacing; spacing: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              Title { text: "Steady keyboard light" }
              Caption { text: root.audioOn ? "AUDIO-REACTIVE (stop it to hold steady)" : (root.kbdLevel > 0 ? "ON · held by the governor" : "OFF") }
            }
            ToggleSwitch {
              id: kSteady
              anchors.verticalCenter: parent.verticalCenter
              checked: root.kbdLevel > 0 && !root.audioOn; busy: root.busy; enabled: root.govOnline
              foreground: root.bar.foreground; accent: root.bar.foreground
              onToggled: root.run(["keys", "audio", "brightness", (root.kbdLevel > 0 && !root.audioOn) ? "0" : "100"])
            }
          }
        }

        // =========================================================== OC
        Page {
          tabId: "oc"; spacing: Style.space(12)
          Row {
            width: parent.width; spacing: Style.space(8)
            Column { width: parent.width - stockBtn.width - parent.spacing; spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
              Title { text: String(root.gpu.name || "GPU") }
              Caption { text: (root.stockNow ? "STOCK CLOCKS" : "TUNED · " + root.signed(root.curGpc) + " / " + root.signed(root.curMem) + " MHz · PL " + root.curPl1 + "/" + root.curPl2 + " W")
                          + " · CAPS " + root.gpcMax + "/" + root.memMax + " · " + root.pl1Max + "/" + root.pl2Max + " W"
                        color: root.stockNow ? root.cMute : root.cWarn } }
            Button { id: stockBtn; anchors.verticalCenter: parent.verticalCenter; iconText: "󰜉"; iconSize: Style.font.title; text: "Stock"
              fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true; active: !root.stockNow
              onClicked: root.run(["tweak", "stock"]) }
          }
          Tiles {
            Tile { icon: "󰢮"; label: "CORE"; value: String(Number(root.ggpu.clockGr || root.gpu.clockGr || 0)); unit: "MHz" }
            Tile { icon: "󰍛"; label: "MEM"; value: String(Number(root.ggpu.clockMem || root.gpu.clockMem || 0)); unit: "MHz" }
            Tile { icon: "󰔏"; label: "GPU"; value: String(Number(root.ggpu.temp || root.gpu.temp || 0)); unit: "°C"; hot: Number(root.ggpu.temp || 0) >= Number(root.limits.gpu_temp_max || 87) }
            Tile { icon: "󱐋"; label: "GPU"; value: String(Math.round(Number(root.ggpu.powerW || root.gpu.power || 0))); unit: "W" }
            Tile { icon: "󰘚"; label: "VRAM"; value: String(Number(root.gpu.vramUsed || 0)); unit: "MB" }
          }
          Note { text: "Every change here asks for your password (polkit) and is clamped to the governor's caps. The governor re-checks every 3 s and reverts anything above a cap; a hard crash while an offset is active lowers the cap below it automatically. Caps never exceed +300/+1500 MHz and 45/115 W by design." }
          Section { text: "VRAM BY APP" }
          Column { width: parent.width; spacing: Style.spacing.labelGap
            Repeater {
              model: root.gpu.processes || []
              Pair { required property var modelData; label: String(modelData.name || "?"); value: Number(modelData.vramMB || 0) + " MB" }
            }
          }
          Note { visible: !(root.gpu.processes && root.gpu.processes.length); text: "No process is using the discrete GPU right now — this laptop's desktop runs on the Intel iGPU; an app only shows up here once it's actually launched on the RTX 4050 (PRIME offload)." }
          Section { text: "GPU CLOCK OFFSET (CAPPED)" }
          Note { text: "Type a value and press Enter (or Apply). No sliders here on purpose — a stray scroll can never change a clock." }
          Column { width: parent.width; spacing: Style.space(8); enabled: root.govOnline; opacity: root.govOnline ? 1 : 0.45
            NumField { id: fGpc; label: "Core offset"; unit: "MHz"; minimum: Number(root.limits.gpc_min || -300); maximum: root.gpcMax; current: root.curGpc
              onApply: function(v) { root.run(["tweak", "set", "gpc", String(v), "mem", String(root.curMem)]) } }
            NumField { id: fMem; label: "Memory offset"; unit: "MHz"; minimum: Number(root.limits.mem_min || -500); maximum: root.memMax; current: root.curMem
              onApply: function(v) { root.run(["tweak", "set", "gpc", String(root.curGpc), "mem", String(v)]) } }
          }
          Section { text: "CPU POWER LIMITS (RAPL ONLY · NEVER MSR)" }
          Column { width: parent.width; spacing: Style.space(8); enabled: root.govOnline; opacity: root.govOnline ? 1 : 0.45
            NumField { label: "PL1 sustained"; unit: "W"; minimum: 15; maximum: root.pl1Max; current: root.curPl1
              onApply: function(v) { root.run(["tweak", "set", "pl1", String(v), "pl2", String(Math.max(v, root.curPl2))]) } }
            NumField { label: "PL2 turbo"; unit: "W"; minimum: 25; maximum: root.pl2Max; current: root.curPl2
              onApply: function(v) { root.run(["tweak", "set", "pl1", String(Math.min(root.curPl1, v)), "pl2", String(v)]) } }
          }
          Section { text: "TWO LOCKS" }
          Row { width: parent.width; spacing: Style.space(8)
            Text { text: "󰌾"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column { width: parent.width - parent.children[0].implicitWidth - parent.spacing; spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
              Title { text: "Lock 1 — change lock" }
              Caption { text: "EVERY OFFSET / LIMIT CHANGE ASKS FOR YOUR PASSWORD (POLKIT)" } } }
          Row { width: parent.width; spacing: Style.space(8)
            Text { text: (root.lockGpc > 0 || root.lockMem > 0) ? "󰦝" : "󰦞"; color: (root.lockGpc > 0 || root.lockMem > 0) ? root.cBad : root.cInsight
                   font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column { width: parent.width - parent.children[0].implicitWidth - parent.spacing; spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
              Title { text: "Lock 2 — crash lock" }
              Caption { color: (root.lockGpc > 0 || root.lockMem > 0) ? root.cBad : root.cMute
                text: (root.lockGpc > 0 || root.lockMem > 0)
                  ? "LOCKED: CORE ≥ +" + (root.lockGpc > 0 ? root.lockGpc : "—") + " · MEM ≥ +" + (root.lockMem > 0 ? root.lockMem : "—") + " MHz PRECEDED A HARD CRASH"
                  : "NO CRASH-LOCKED VALUES" } } }
          Note { text: "Values that were live when the laptop hard-crashed are crash-locked: the normal loosen path refuses them even with your password. Releasing a crash lock is a separate action with its own warning dialog and a second password." }
          Row { visible: root.lockGpc > 0 || root.lockMem > 0; width: parent.width; spacing: Style.space(6)
            Button { visible: root.lockGpc > 0; width: (parent.width - parent.spacing) / 2; iconText: "󰦝"; iconSize: Style.font.title; text: "Release core lock (+" + root.lockGpc + ")"
              fontSize: Style.font.bodySmall; foreground: root.cBad; fontFamily: root.bar.fontFamily; bordered: true; onClicked: root.run(["tweak", "unlock-crashed", "gpc"]) }
            Button { visible: root.lockMem > 0; width: (parent.width - parent.spacing) / 2; iconText: "󰦝"; iconSize: Style.font.title; text: "Release mem lock (+" + root.lockMem + ")"
              fontSize: Style.font.bodySmall; foreground: root.cBad; fontFamily: root.bar.fontFamily; bordered: true; onClicked: root.run(["tweak", "unlock-crashed", "mem"]) } }
          Section { text: "CAPS (LOOSENING NEEDS YOUR PASSWORD)" }
          Row { width: parent.width; spacing: Style.space(20)
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Core cap"; value: "+" + root.gpcMax + " MHz" }
              Pair { label: "Memory cap"; value: "+" + root.memMax + " MHz" } }
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "PL1 / PL2 cap"; value: root.pl1Max + " / " + root.pl2Max + " W" }
              Pair { label: "Set by"; value: String(root.limits.source || "—").slice(0, 34) } } }
          ButtonRow {
            model: [ { id: "50", label: "Core cap +50" }, { id: "100", label: "+100" }, { id: "150", label: root.lockGpc > 0 && 150 >= root.lockGpc ? "󰦝 +150" : "+150" }, { id: "200", label: root.lockGpc > 0 && 200 >= root.lockGpc ? "󰦝 +200 LOCKED" : "+200" } ]
            activeId: String(root.gpcMax)
            onPicked: function(m) { root.run(["tweak", Number(m.id) <= root.gpcMax ? "tighten" : "loosen", "gpc_max", m.id]) }
          }
          ButtonRow {
            model: [ { id: "0", label: "Mem cap 0" }, { id: "300", label: "+300" }, { id: "500", label: root.lockMem > 0 && 500 >= root.lockMem ? "󰦝 +500" : "+500" }, { id: "600", label: root.lockMem > 0 && 600 >= root.lockMem ? "󰦝 +600 LOCKED" : "+600" } ]
            activeId: String(root.memMax)
            onPicked: function(m) { root.run(["tweak", Number(m.id) <= root.memMax ? "tighten" : "loosen", "mem_max", m.id]) }
          }
        }

        // =========================================================== FANS
        Page {
          tabId: "fans"; spacing: Style.space(12)
          Meter { label: "Fan 1 (CPU)"; value: root.rpm1; maxValue: Number(root.fan.max1 || 5800); text: root.rpm1 + " rpm"; hot: root.maxed }
          Meter { label: "Fan 2 (GPU)"; value: root.rpm2; maxValue: Number(root.fan.max2 || 6100); text: root.rpm2 + " rpm"; hot: root.maxed }
          Tiles {
            Tile { icon: "󰔏"; label: "CPU"; value: String(root.cpuNow); unit: "°C"; hot: root.cpuNow >= 90 }
            Tile { icon: "󰢮"; label: "GPU"; value: root.gpuTempFan === "IDLE" ? "—" : String(root.gpuTempFan); unit: root.gpuTempFan === "IDLE" ? "idle" : "°C" }
            Tile { icon: "󱐋"; label: "DRAW"; value: String(Math.round(Number(root.power.systemW || 0))); unit: "W" }
          }
          Caption { text: root.fanOnline ? "FAN BACKEND OK · KERNEL hp-wmi PATH (NO EC POKING)" : "FAN BACKEND OFFLINE" }
          Section { text: "FAN MODE" }
          ButtonRow {
            model: root.fanModes; activeId: root.activeFanMode
            onPicked: function(m) { root.run(m.args ? m.args : ["fan", "manual", String(root.manualLevel)]) }
          }
          Column {
            width: parent.width; spacing: Style.space(6); opacity: root.manual ? 1 : 0.45
            Pair { label: "Manual level"; value: root.manualLevel + " / 8" }
            PanelSlider { width: parent.width; bar: root.bar; minimum: 1; maximum: 8; step: 1; integer: true; tickCount: 8
              value: root.manualLevel
              onReleased: function(v) { root.manualLevel = Math.round(v); root.run(["fan", "manual", String(root.manualLevel)]) } }
          }
          Note { text: "Fans go through victus-backend and the kernel hp-wmi driver; no password needed and no crash risk. The guardian warns when fans sit at max while the laptop is cool (bearing wear)." }
        }

        // =========================================================== POWER
        Page {
          tabId: "power"; spacing: Style.space(12)
          Row { width: parent.width
            Column { width: parent.width; spacing: Style.space(2)
              Title { text: root.power.ac ? "On AC adapter · " + String((root.power.input && root.power.input.adapterRatedW) || "?") + " W" : "On battery" }
              Caption { text: "PROFILE " + String(root.gcpu.profile || "?").toUpperCase() + " · EPP " + String(root.gcpu.epp || "?").toUpperCase() + " · PL " + root.curPl1 + "/" + root.curPl2 + " W" } } }
          Meter { label: "System draw"; value: Number(root.power.systemW || 0); maxValue: 200; text: Number(root.power.systemW || 0) + " W" }
          Tiles {
            Tile { icon: "󰍛"; label: "CPU"; value: String(Math.round(Number(root.power.cpuW || 0))); unit: "W" }
            Tile { icon: "󰢮"; label: "GPU"; value: String(Math.round(Number(root.power.gpuW || 0))); unit: "W" }
            Tile { icon: "󰔏"; label: "PKG"; value: String(Number(root.gcpu.temp || root.cpuNow || 0)); unit: "°C"; hot: Number(root.gcpu.temp || 0) >= Number(root.limits.cpu_temp_max || 95) }
          }
          Section { text: "POWER PROFILE (NO PASSWORD · NO OVERCLOCK)" }
          ButtonRow {
            model: [ { id: "power-saver", icon: "󰌪", label: "Saver" }, { id: "balanced", icon: "󰗑", label: "Balanced" }, { id: "performance", icon: "󱐋", label: "Performance" } ]
            activeId: String(root.gcpu.profile || "") === "low-power" ? "power-saver" : String(root.gcpu.profile || "")
            onPicked: function(m) { root.run(["power", "profile", m.id]) }
          }
          Note { text: "Performance = stock clocks with full boost and the GPU's full 75 W TGP — this is what fixed the 50 fps problem, not the overclock. Saver parks the CPU near 1 GHz." }
          Section { text: "THERMAL GUARD (SPIKE-AWARE)" }
          Row { width: parent.width; spacing: Style.space(8)
            Text { text: root.thermalActive ? "󰈸" : "󰔏"; color: root.thermal === "crit" ? root.cBad : root.thermalActive ? root.cWarn : root.cInsight
                   font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
            Column { width: parent.width - parent.children[0].implicitWidth - parent.spacing; spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
              Title { text: root.thermal === "crit" ? "CRITICAL — power cut to " + (root.limits.crit_pl || [20,35]).join("/") + " W, low-power, fans max"
                          : root.thermal === "hot" ? "HOT — fans max, PL " + (root.limits.hot_pl || [35,55]).join("/") + " W, offsets cleared"
                          : "Normal — watching every 3 s" }
              Caption { visible: root.thermalActive && gov.thermal_since !== undefined && gov.thermal_since !== null; color: root.cWarn
                text: "SENSED AT " + root.fmtTS(gov.thermal_since || 0) + " · " + root.timeAgo(gov.thermal_since || 0) + " · RELEASES AFTER " + Number(root.limits.cool_hold_s || 60) + " S BELOW " + Number(root.limits.cool_c || 75) + " °C" }
              Caption { text: "TRIGGERS: CPU ≥ " + Number(root.limits.cpu_hot || 88) + " °C · GPU ≥ " + Number(root.limits.gpu_hot || 83) + " °C · SPIKE ≥ " + Number(root.limits.spike_c || 12) + " °C/TICK · CRIT ≥ " + Number(root.limits.cpu_crit || 94) + " °C · RELEASE < " + Number(root.limits.cool_c || 75) + " °C FOR " + Number(root.limits.cool_hold_s || 60) + " S" } } }
          Section { text: "GOVERNOR POWER RULES" }
          Column { width: parent.width; spacing: Style.spacing.labelGap
            Pair { label: "PL1 / PL2 hard cap"; value: root.pl1Max + " / " + root.pl2Max + " W (Intel spec 45 / 115)" }
            Pair { label: "GPU thermal revert"; value: "≥ " + Number(root.limits.gpu_temp_max || 87) + " °C → offsets to stock" }
            Pair { label: "CPU thermal revert"; value: "≥ " + Number(root.limits.cpu_temp_max || 95) + " °C → PL to stock" }
            Pair { label: "MSR 0x610 writes"; value: "FORBIDDEN (two power-cuts on Aug 28)" } }
        }

        // =========================================================== GUARD
        Page {
          tabId: "guard"; spacing: Style.space(12)
          Row {
            width: parent.width; spacing: Style.space(8)
            Column {
              width: parent.width - gIns.width - parent.spacing; spacing: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              Title { text: "Guardian" }
              Caption { text: (root.guard.active ? "WATCHING · " : "STOPPED · ") + Number(root.guard.learned || 0) + "/" + Number(root.guard.bands || 0) + " BANDS · " + Number(root.guard.samples_mb || 0) + " MB" }
            }
            Button { id: gIns; anchors.verticalCenter: parent.verticalCenter; iconText: "󰧑"; iconSize: Style.font.title; text: "Insights"
              fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true; onClicked: root.loadInsights() }
          }
          Caption { visible: String(root.insight.headline || "") !== ""; text: String(root.insight.headline || ""); color: root.lvlColor(String(root.insight.level || "info")) }
          Caption { visible: root.insight.generated !== undefined; color: root.cMute
            text: "Checked " + root.timeAgo(root.insight.generated) + " · last " + Number(root.insight.hours || 0) + "h window (" + Number(root.insight.span_h || 0).toFixed(1) + "h of data)" }
          Column {
            width: parent.width; spacing: Style.space(8)
            Repeater {
              model: root.insight.cards || []
              InsightCard { required property var modelData; width: parent.width
                accent: root.lvlColor(String(modelData.level || "info")); icon: String(modelData.icon || "")
                title: String(modelData.title || ""); metric: String(modelData.metric || "")
                detail: String(modelData.detail || "") + "\n󰥔 " + (modelData.t !== undefined ? root.fmtTS(modelData.t) : (root.insight.generated !== undefined ? "analysed " + root.fmtTS(root.insight.generated) + " (" + root.timeAgo(root.insight.generated) + ")" : "")) }
            }
          }
          Note { visible: !(root.insight.cards && root.insight.cards.length); text: "Press Insights for a plain-English health check of the last 24 h." }
          Section { visible: !!(root.guard.alerts && root.guard.alerts.length); text: "RECENT WARNINGS" }
          Column {
            width: parent.width; spacing: Style.space(6)
            Repeater {
              model: root.guard.alerts || []
              Column { required property var modelData; width: parent.width; spacing: Style.space(1)
                Row { width: parent.width; spacing: Style.space(6)
                  Text { text: root.fmtTS(modelData.t); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                  Text { text: "· " + root.timeAgo(modelData.t); color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                  Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[1].implicitWidth - alertTitle.implicitWidth - parent.spacing * 3); height: 1 }
                  Text { id: alertTitle; text: String(modelData.title || ""); color: modelData.critical ? root.cBad : root.cWarn; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true } }
                Note { text: String(modelData.body || ""); maximumLineCount: 2; elide: Text.ElideRight } }
            }
          }
          ButtonRow {
            model: [ { id: "30", label: "Mute 30m" }, { id: "180", label: "Mute 3h" }, { id: "0", label: "Unmute" } ]
            activeId: ""
            onPicked: function(m) { root.run(["guard", "mute", m.id]) }
          }
          Section { text: "TIMELINE — EVERYTHING THE GUARDS DID (NEWEST FIRST)" }
          Column {
            width: parent.width; spacing: 0
            Repeater {
              model: root.timeline
              Item {
                required property var modelData
                required property int index
                width: parent.width; implicitHeight: tlRow.implicitHeight + Style.space(8)
                Rectangle { x: Style.space(9); width: Style.space(2); height: parent.height; color: root.cFill; visible: index < root.timeline.length - 1 || index === 0 }
                Rectangle { x: Style.space(6); y: Style.space(8); width: Style.space(8); height: width; radius: width / 2; color: root.lvlColor(String(modelData.level || "info")) }
                Row {
                  id: tlRow
                  x: Style.space(22); y: Style.space(4); width: parent.width - Style.space(22); spacing: Style.space(8)
                  Text { text: new Date(Number(modelData.t) * 1000).toLocaleString(Qt.locale(), "dd MMM HH:mm"); color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(84) }
                  Column { width: parent.width - Style.space(84) - parent.spacing; spacing: Style.space(1)
                    Row { width: parent.width; spacing: Style.space(6)
                      Text { text: String(modelData.title || ""); color: root.lvlColor(String(modelData.level || "info")); font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; width: parent.width - srcTag.implicitWidth - parent.spacing }
                      Text { id: srcTag; text: String(modelData.src || "").toUpperCase(); color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.letterSpacing: 1 } }
                    Text { visible: String(modelData.detail || "") !== ""; text: String(modelData.detail || ""); color: root.bar.foreground; opacity: 0.6; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; width: parent.width; maximumLineCount: 2; elide: Text.ElideRight }
                  }
                }
              }
            }
            Note { visible: !root.timeline.length; text: "No guard events recorded yet." }
          }
        }

        // =========================================================== BATTERY
        Page {
          id: battCol
          tabId: "battery"; spacing: Style.space(12)
          readonly property var tr: root.batt.trend || {}
          Row { width: parent.width
            Column { width: parent.width; spacing: Style.space(2)
              Title { text: String(root.batt.model || "Battery") + " · " + Number(root.batt.capacity || 0) + "%" }
              Caption { text: String(root.batt.status || "") + " · " + Number(root.batt.cycles || 0) + " CYCLES" + (root.capLive ? " · 80% CAP ON" : "") } } }
          Section { text: "CHARGE" }
          Meter { label: "Charge"; value: Number(root.batt.capacity || 0); maxValue: 100
            text: Number(root.batt.capacity || 0) + "% · " + Number(root.batt.energyNowWh || 0) + " / " + Number(root.batt.energyFullWh || 0) + " Wh"
            color2: root.capLive ? root.cInsight : root.bar.foreground }
          Row {
            width: parent.width; spacing: Style.space(20)
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Status"; value: String(root.batt.status || "—") }
              Pair { label: "Voltage"; value: Number(root.batt.voltageV || 0).toFixed(2) + " V" } }
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Cycles"; value: String(root.batt.cycles || 0) }
              Pair { label: "Health"; value: Number(root.batt.healthPct || 0) + "% (wear " + Number(root.batt.wearPct || 0) + "%)" } }
          }
          Section { visible: battCol.tr.points > 0; text: "TREND" }
          Column { width: parent.width; spacing: Style.spacing.labelGap; visible: battCol.tr.points > 0
            Pair { label: "Health"; value: Number(battCol.tr.healthStart || 0) + "% → " + Number(battCol.tr.healthNow || 0) + "% / " + Number(battCol.tr.spanDays || 0) + " d" }
            Pair { label: "Held full on AC"; value: Number(battCol.tr.hoursAt100OnAC || 0) + " h" } }
          Section { text: "80% CHARGE CAP (HP ADAPTIVE BATTERY EXTENDER)" }
          Pair { label: "Status"; value: root.capLive ? "ON · firmware-enforced" : "OFF" }
          Note { text: "HP's EC re-asserts this bit within ~0.6 s of any attempt to clear it from software — verified, it cannot be disabled from Linux. To charge past ~80%, use BIOS: F10 → Battery Health Manager → Maximize battery." }
          Section { text: "UNPLUG REMINDER" }
          ButtonRow {
            model: [ { id: "on", icon: "󰂜", label: "Remind at 80%" }, { id: "off", icon: "󰂎", label: "Off" } ]
            activeId: root.batt.guardActive ? "on" : "off"
            onPicked: function(m) { root.run(m.id === "on" ? ["battery", "guard", "on", "80"] : ["battery", "guard", "off"]) }
          }
        }

        // =========================================================== SYSTEM
        Page {
          id: sysCol
          tabId: "system"; spacing: Style.space(12)
          readonly property var v: root.omatop && root.omatop.vitals ? root.omatop.vitals : null
          Section { text: "SYSTEM" }
          Meter { label: "CPU load"; value: sysCol.v ? Number(sysCol.v.cpu.total) : 0; maxValue: 100
            text: sysCol.v ? root.pct(sysCol.v.cpu.total) + (sysCol.v.cpu.freq ? " · " + (sysCol.v.cpu.freq / 1000).toFixed(1) + " GHz" : "") : "sampler starting…"
            hot: sysCol.v ? Number(sysCol.v.cpu.total) > 85 : false }
          Meter { label: "Memory"; value: sysCol.v ? Number(sysCol.v.mem.used) : 0; maxValue: sysCol.v ? Math.max(1, Number(sysCol.v.mem.total)) : 1
            text: sysCol.v ? root.fmtMB(Math.round(sysCol.v.mem.used / 1048576)) + " / " + root.fmtMB(Math.round(sysCol.v.mem.total / 1048576)) : "—"; hot: false }
          Meter { label: "VRAM"; value: Number(root.gpu.vramUsed || 0); maxValue: Math.max(1, Number(root.gpu.vramTotal || 1))
            text: Number(root.gpu.vramUsed || 0) + " / " + Number(root.gpu.vramTotal || 0) + " MB"; hot: false }
          Row {
            width: parent.width; spacing: Style.space(20)
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Pressure"; value: root.omatop && root.omatop.pressure ? String(root.omatop.pressure.level) : "—" }
              Pair { label: "Culprit"; value: root.omatop && root.omatop.culprit ? String(root.omatop.culprit) : "none" } }
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "GPU"; value: Number(root.gpu.temp || 0) + " °C · " + root.pct(root.gpu.util) }
              Pair { label: "Fans"; value: Math.max(root.rpm1, root.rpm2) + " rpm" } }
          }
          Section { text: "SERVICES" }
          Column { width: parent.width; spacing: Style.spacing.labelGap
            Repeater { model: Object.keys(root.gov.units || {})
              Pair { required property var modelData; label: String(modelData); value: String((root.gov.units || {})[modelData] || "?").toUpperCase() } } }
          Button {
            width: parent.width; iconText: "󰍛"; iconSize: Style.font.title; text: "Open omatop overlay"
            fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true
            onClicked: { root.close(); if (root.bar && root.bar.shell) root.bar.shell.toggle("ryanyogan.omatop", "{}") }
          }
          Section { text: "PRIVACY" }
          KillSwitch { icon: "󰄀"; title: "Camera"; state: root.camState; detail: "USB de-authorize + driver unload; persists across replug."
            onToggled: function(on) { root.run(["cam", on ? "on" : "off"]) } }
          KillSwitch { icon: "󰍬"; title: "Microphone"; state: root.micState; detail: "WirePlumber hides every capture node and the codec capture path is muted. Speakers keep working; PipeWire is never restarted."
            onToggled: function(on) { root.run(["mic", on ? "on" : "off"]) } }
          Section { text: "LID / CLAMSHELL" }
          KillSwitch {
            icon: "󰛨"; title: "Clamshell mode"; state: root.clam.enabled === true ? "on" : "off"; onLabel: "ON"; offLabel: "OFF"
            detail: (root.clam.enabled === true ? "Lid close keeps the session awake on the external display." : "Lid close = normal (lock / suspend).")
            onToggled: function(on) { root.run(["clamshell", on ? "on" : "off"]) }
          }
        }

        // =========================================================== GOVERNOR
        Page {
          tabId: "gov"; spacing: Style.space(12)
          Row {
            width: parent.width; spacing: Style.space(8)
            Column { width: parent.width - govBtn.width - parent.children[1].width - parent.spacing * 2; spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
              Title { text: "AI Governor" }
              Caption { text: !root.govOnline ? "DAEMON OFFLINE — " + String(root.gov.err || "not installed?")
                          : "ONLINE · UP " + Math.round(Number(root.gov.uptime || 0) / 60) + " MIN · " + Number(root.gov.enforcements || 0) + " ENFORCEMENTS · v" + String(root.gov.version || "?")
                        color: root.govOnline ? root.cMute : root.cWarn } }
            Button { anchors.verticalCenter: parent.verticalCenter; iconText: "󰜉"; iconSize: Style.font.title; text: "Restore defaults"
              fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true
              onClicked: root.run(["tweak", "restore-defaults"]) }
            Button { id: govBtn; anchors.verticalCenter: parent.verticalCenter; iconText: root.aiReview ? "󰀦" : "󰧑"; iconSize: Style.font.title
              text: root.aiReview ? "Crash analysis (Opus 5)" : root.aiNudge ? "Review event (Sonnet 5)" : "Review now (Sonnet 5)"
              fontSize: Style.font.bodySmall; foreground: root.aiReview ? root.cWarn : root.bar.foreground; fontFamily: root.bar.fontFamily; bordered: true; active: root.aiReview
              onClicked: root.runAi([root.aiReview ? "crash" : "review"]) }
          }
          Tiles {
            Tile { icon: "󰢮"; label: "OFFSET"; value: root.signed(root.curGpc) + "/" + root.signed(root.curMem); unit: "MHz"; hot: root.curGpc > root.gpcMax || root.curMem > root.memMax }
            Tile { icon: "󱐋"; label: "PL"; value: root.curPl1 + "/" + root.curPl2; unit: "W"; hot: root.curPl1 > root.pl1Max || root.curPl2 > root.pl2Max }
            Tile { icon: "󰓅"; label: "EC"; value: root.ecTripped ? "TRIP" : String(Number(root.gec.rate || 0)); unit: root.ecTripped ? "" : "w/s"; hot: root.ecTripped }
            Tile { icon: "󰀦"; label: "CRASHES"; value: String(root.incidents.filter(function(i) { return i.kind === "hard_crash" }).length); unit: "logged" }
          }
          Row { visible: root.ecTripped; width: parent.width; spacing: Style.space(8)
            Note { width: parent.width - ecResetBtn.width - parent.spacing; anchors.verticalCenter: parent.verticalCenter; color: root.cWarn; opacity: 1
              text: "The EC arbiter tripped its write budget and stopped driving the keys (" + String(root.gec.err || "") + "). Re-arm it after checking the Keys budget." }
            Button { id: ecResetBtn; text: "Re-arm EC"; fontSize: Style.font.bodySmall; foreground: root.cWarn; fontFamily: root.bar.fontFamily; bordered: true; onClicked: root.run(["gov", "ec-reset"]) } }
          Note { text: "The daemon is deterministic and runs from every boot: it samples every 3 s, enforces the caps, keeps a crash memory, and only accepts AI proposals that make limits tighter. Loosening always needs your password." }
          Section { text: "MODELS" }
          Row { width: parent.width; spacing: Style.space(20)
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Periodic review"; value: String((root.ai.conf || {}).model_review || "claude-sonnet-5") }
              Pair { label: "Schedule"; value: "login + every 30 min" } }
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Post-crash analysis"; value: String((root.ai.conf || {}).model_crash || "claude-opus-5") }
              Pair { label: "Last run"; value: (root.ai.runs && root.ai.runs.length) ? root.timeAgo(root.ai.runs[root.ai.runs.length - 1].t) + " · " + String(root.ai.runs[root.ai.runs.length - 1].kind) : "never" } } }
          Section { text: "AI USAGE (ROLLING " + Number((root.ai.usage || {}).window_h || 5) + " H WINDOW · HARD BUDGET)" }
          Meter { label: "Tokens used"; value: Number((root.ai.usage || {}).tokens || 0); maxValue: Math.max(1, Number((root.ai.usage || {}).budget_tokens || 120000))
            text: Number((root.ai.usage || {}).tokens || 0).toLocaleString(Qt.locale(), "f", 0) + " / " + Number((root.ai.usage || {}).budget_tokens || 120000).toLocaleString(Qt.locale(), "f", 0) + " (" + Number((root.ai.usage || {}).pct_tokens || 0) + "%)"
            hot: Number((root.ai.usage || {}).pct_tokens || 0) >= 90 }
          Row { width: parent.width; spacing: Style.space(20)
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Runs in window"; value: Number((root.ai.usage || {}).runs || 0) + " / " + Number((root.ai.usage || {}).budget_runs || 8) }
              Pair { label: "Opus runs in window"; value: Number((root.ai.usage || {}).opus_runs || 0) + " / " + Number((root.ai.usage || {}).budget_opus_runs || 2) } }
            Column { width: (parent.width - parent.spacing) / 2; spacing: Style.spacing.labelGap
              Pair { label: "Lifetime"; value: Number(((root.ai.usage || {}).lifetime || {}).runs || 0) + " runs · " + Number(((root.ai.usage || {}).lifetime || {}).tokens || 0).toLocaleString(Qt.locale(), "f", 0) + " tok" }
              Pair { label: "Est. API cost (window)"; value: "$" + Number((root.ai.usage || {}).cost_usd || 0).toFixed(3) } } }
          Note { text: "Budget defaults: 8 runs / 120k tokens / 2 Opus runs per 5 h ≈ 5–10 % of a Claude 5-hour session. Runs beyond the budget are skipped (logged), never queued. Edit ~/.config/powerhouse/ai.json to change." }
          Section { text: "INCIDENTS (GOVERNOR MEMORY)" }
          Column { width: parent.width; spacing: Style.space(6)
            Repeater {
              model: root.incidents.slice().reverse().slice(0, 6)
              InsightCard { required property var modelData; width: parent.width
                accent: modelData.kind === "hard_crash" ? root.cBad : root.cWarn
                icon: modelData.kind === "hard_crash" ? "󰀦" : "󰒃"
                title: modelData.kind === "hard_crash" ? "Hard crash — caps tightened" : "Enforcement"
                metric: root.fmtT(modelData.t)
                detail: modelData.kind === "hard_crash"
                  ? "Active: " + JSON.stringify((modelData.last_state || {}).active || {}).slice(0, 140) + "  →  changed " + JSON.stringify(modelData.changed || {})
                  : String(modelData.what || "") }
            }
            Note { visible: !root.incidents.length; text: "No incidents recorded by the governor yet." }
          }
          Section { text: "LESSONS (AI MEMORY · TAIL)" }
          Rectangle { width: parent.width; radius: Style.space(6); color: root.cFill; implicitHeight: lessonsText.implicitHeight + Style.space(16)
            Text { id: lessonsText; anchors.fill: parent; anchors.margins: Style.space(8); wrapMode: Text.WordWrap
              text: String(root.ai.lessons_tail || "(empty)"); color: root.bar.foreground; opacity: 0.8; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption } }
          Section { visible: root.aiOut !== ""; text: "LAST AI OUTPUT" }
          Rectangle { visible: root.aiOut !== ""; width: parent.width; radius: Style.space(6); color: root.cFill; implicitHeight: aiText.implicitHeight + Style.space(16)
            Text { id: aiText; anchors.fill: parent; anchors.margins: Style.space(8); wrapMode: Text.WordWrap
              text: root.aiOut.slice(0, 2500); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption } }
        }
      }
      }

      // ---------- scrollbar (drawn by hand so it follows the bar theme) ----------
      Rectangle {
        visible: flick.scrollable
        anchors.right: parent.right; anchors.rightMargin: -Style.space(2)
        anchors.top: flick.top; anchors.bottom: flick.bottom
        width: Style.space(5); radius: width / 2; color: root.cFill
        Rectangle {
          width: parent.width; radius: parent.radius; color: root.bar.foreground; opacity: 0.55
          height: Math.max(Style.space(24), parent.height * flick.visibleArea.heightRatio)
          y: (parent.height - height) * (flick.contentHeight > flick.height ? flick.contentY / (flick.contentHeight - flick.height) : 0)
          Behavior on y { NumberAnimation { duration: 80 } }
        }
        MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4)
          onPressed: function(m) { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, (m.y / height) * flick.contentHeight - flick.height / 2)) }
          onPositionChanged: function(m) { if (pressed) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, (m.y / height) * flick.contentHeight - flick.height / 2)) } }
      }
      Caption {
        visible: flick.scrollable && flick.contentY < flick.contentHeight - flick.height - 2
        anchors.bottom: flick.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: implicitWidth
        text: "▾ SCROLL FOR MORE ▾"; opacity: 0.7
      }
    }
  }

  // ---------------------------------------------------------------- components
  component Page: Column {
    id: page
    property string tabId: ""
    readonly property bool on: root.tab === tabId
    width: parent.width
    visible: on
    transform: Translate { id: pageShift; y: 0 }
    onOnChanged: if (on) pageIn.restart()
    ParallelAnimation {
      id: pageIn
      NumberAnimation { target: page; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
      NumberAnimation { target: pageShift; property: "y"; from: Style.space(10); to: 0; duration: 300; easing.type: Easing.OutCubic }
    }
  }
  component Tiles: Row {
    width: parent.width; spacing: Style.space(8)
    readonly property real cellWidth: (width - spacing * (children.length - 1)) / children.length
  }
  component Tile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property string value: ""
    property string unit: ""
    property bool hot: false
    width: parent.cellWidth
    implicitHeight: tileCol.implicitHeight + Style.space(22)
    radius: Style.space(8); color: root.cFill
    border.width: 1; border.color: hot ? root.cBad : "transparent"
    Behavior on border.color { ColorAnimation { duration: 300 } }
    Column {
      id: tileCol
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(12); spacing: Style.space(4)
      Row { spacing: Style.space(5)
        Text { text: tile.icon; color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
        Text { text: tile.label; color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2; anchors.verticalCenter: parent.verticalCenter } }
      Row { spacing: Style.space(3)
        Text { text: tile.value; color: tile.hot ? root.cBad : root.bar.foreground
          font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; font.bold: true
          Behavior on color { ColorAnimation { duration: 300 } } }
        Text { text: tile.unit; color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4) } }
    }
  }
  component Title: Text {
    color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title
    font.bold: true; elide: Text.ElideRight; width: parent.width
  }
  component Caption: Text {
    color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
    font.bold: true; font.letterSpacing: 1.2; elide: Text.ElideRight; width: parent.width
  }
  component Section: PanelSectionHeader { foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
  component Note: Text {
    width: parent.width; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.55
    font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption
  }
  component Pair: Row {
    property string label: ""
    property string value: ""
    width: parent.width; spacing: Style.space(8)
    Text { text: label; color: root.bar.foreground; opacity: 0.6; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text { text: value; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideLeft; maximumLineCount: 1 }
  }
  component Meter: Item {
    property string label: ""
    property real value: 0
    property real maxValue: 1
    property string text: ""
    property bool hot: false
    property color color2: hot ? root.cBad : root.bar.foreground
    width: parent.width
    implicitHeight: meterLabels.implicitHeight + Style.space(12)
    Pair { id: meterLabels; label: parent.label; value: parent.text }
    Rectangle {
      anchors.top: meterLabels.bottom; anchors.topMargin: Style.space(6)
      width: parent.width; height: Style.space(9); radius: height / 2; color: root.cFill
      Rectangle {
        height: parent.height; radius: parent.radius; color: parent.parent.color2
        width: Math.max(height, parent.width * Math.min(1, parent.parent.value / Math.max(1, parent.parent.maxValue)))
        Behavior on width { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
      }
    }
  }
  component NumField: Item {
    id: nf
    property string label: ""
    property string unit: ""
    property int minimum: 0
    property int maximum: 100
    property int current: 0
    signal apply(int value)
    readonly property int typed: parseInt(nfInput.text, 10)
    readonly property bool valid: !isNaN(typed) && typed >= minimum && typed <= maximum
    readonly property bool dirty: valid && typed !== current
    width: parent.width
    implicitHeight: nfRow.implicitHeight
    onCurrentChanged: if (!nfInput.activeFocus) nfInput.text = String(current)
    Component.onCompleted: nfInput.text = String(current)
    Row {
      id: nfRow
      width: parent.width; spacing: Style.space(8)
      Column { width: parent.width - nfBox.width - nfApply.width - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
        Text { text: nf.label; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
        Caption { text: "NOW " + root.signed(nf.current) + " " + nf.unit + " · ALLOWED " + root.signed(nf.minimum) + " … " + root.signed(nf.maximum) + " " + nf.unit
                  color: nfInput.text !== "" && !nf.valid ? root.cBad : root.cMute } }
      Rectangle { id: nfBox; width: Style.space(110); height: Style.space(32); radius: Style.space(6); color: root.cFill
        border.width: 1; border.color: nfInput.activeFocus ? (nf.valid ? root.bar.foreground : root.cBad) : "transparent"
        TextInput { id: nfInput; anchors.fill: parent; anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(28)
          verticalAlignment: TextInput.AlignVCenter; horizontalAlignment: TextInput.AlignRight
          color: nf.valid || text === "" ? root.bar.foreground : root.cBad; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true
          inputMethodHints: Qt.ImhFormattedNumbersOnly; validator: RegularExpressionValidator { regularExpression: /-?[0-9]{0,4}/ }
          selectByMouse: true; clip: true
          onAccepted: if (nf.dirty) nf.apply(nf.typed) }
        Text { anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter
          text: nf.unit; color: root.cMute; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true } }
      Button { id: nfApply; anchors.verticalCenter: parent.verticalCenter; text: "Apply"; fontSize: Style.font.bodySmall
        foreground: nf.dirty ? root.bar.foreground : root.cMute; fontFamily: root.bar.fontFamily; bordered: true; active: nf.dirty; enabled: nf.dirty
        onClicked: nf.apply(nf.typed) }
    }
  }
  component ButtonRow: Row {
    property var model: []
    property string activeId: ""
    signal picked(var entry)
    width: parent.width; spacing: Style.space(6)
    readonly property real cellWidth: model.length ? (width - spacing * (model.length - 1)) / model.length : 0
    Repeater {
      model: parent.model
      Button {
        required property var modelData
        width: parent.cellWidth
        iconText: modelData.icon || ""
        iconSize: Style.font.title
        text: modelData.label
        fontSize: Style.font.bodySmall
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
        bordered: true
        active: parent.activeId === modelData.id
        opacity: parent.enabled ? 1 : 0.4
        onClicked: parent.picked(modelData)
      }
    }
  }
  component InsightCard: Item {
    property color accent: root.cInfo
    property string icon: ""
    property string title: ""
    property string metric: ""
    property string detail: ""
    implicitHeight: icRow.implicitHeight + Style.space(16)
    Rectangle { anchors.fill: parent; radius: Style.space(6); color: root.cFill }
    Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: Style.space(3); radius: Style.space(2); color: parent.accent }
    Row {
      id: icRow
      anchors.fill: parent; anchors.margins: Style.space(8); anchors.leftMargin: Style.space(14)
      spacing: Style.space(10)
      Text { text: parent.parent.icon; color: parent.parent.accent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; anchors.top: parent.top }
      Column {
        width: parent.width - parent.children[0].implicitWidth - parent.spacing
        spacing: Style.space(2)
        Row {
          width: parent.width
          Text { text: parent.parent.parent.parent.title; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
          Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth); height: 1 }
          Text { text: parent.parent.parent.parent.metric; color: parent.parent.parent.parent.accent; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
        }
        Text { text: parent.parent.parent.detail; width: parent.width; wrapMode: Text.WordWrap; color: root.bar.foreground; opacity: 0.7; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      }
    }
  }
  component KillSwitch: Item {
    property string icon: ""
    property string title: ""
    property string state: "?"
    property string detail: ""
    property string onLabel: "LIVE"
    property string offLabel: "KILLED"
    signal toggled(bool on)
    readonly property bool isOn: state === "on"
    width: parent.width
    implicitHeight: ksRow.implicitHeight
    Row {
      id: ksRow
      width: parent.width; spacing: Style.space(10)
      Text { text: icon; color: isOn ? root.bar.foreground : root.cBad
        font.family: root.bar.fontFamily; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
      Column {
        width: parent.width - parent.children[0].implicitWidth - ksBtn.width - parent.spacing * 2
        spacing: Style.space(2); anchors.verticalCenter: parent.verticalCenter
        Title { text: title }
        Caption { text: state === "absent" ? "NOT PRESENT" : (isOn ? onLabel : offLabel); color: isOn ? root.cMute : root.cBad }
        Note { text: detail }
      }
      Button {
        id: ksBtn
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐥"; iconSize: Style.font.title
        text: isOn ? "Turn off" : "Turn on"
        fontSize: Style.font.bodySmall
        foreground: isOn ? root.bar.foreground : root.cBad
        fontFamily: root.bar.fontFamily
        bordered: true; active: !isOn
        onClicked: toggled(!isOn)
      }
    }
  }
}
