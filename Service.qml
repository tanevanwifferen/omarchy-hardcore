import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Hardcore mode. While `on`, every key press rattles the focused window and
// throws coloured pixels out of the place being typed at, the sides of the
// screen glow and spray sparks, and a combo counter climbs for as long as the
// typing keeps up. It comes in a few flavours (`modes`). Off after a shell
// restart.
//
// The rattle is a Hyprland screen shader that pushes the picture aside inside
// the window's rectangle only. A shader that animates by itself needs the
// `time` uniform, which makes Hyprland give up damage tracking and warn about
// it; so each jolt is a still shader, written out afresh with a new offset
// while keys keep coming, and the shader is cleared when they stop.
//
// A change to this file needs `omarchy restart shell`; saving is not enough.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool on: false
  // Keys are being hit right now.
  property bool typing: false
  // Counts key presses; the sparks answer each one.
  property int beat: 0
  // How hard the typing is going, 0 to 1: up with every key, cooling off
  // by itself. The sides of the screen glow and spray sparks by it.
  property real heat: 0
  // Keys in a row without a pause, and how far that has wound things up.
  property int streak: 0
  readonly property real power: Math.min(1, streak / 80)

  // The flavours. `shake` scales the rattle and `tear` rips rows of the
  // window sideways; `gravity` pulls the sparks down (or, negative, up);
  // `sides`, `floor` and `rain` say where sparks pour in from besides the
  // caret; `glow` fixes the hue of the edge glow, -1 lets it wander.
  readonly property var rainbow: [0.0, 0.09, 0.16, 0.38, 0.52, 0.62, 0.8, 0.9]
  readonly property var modes: [
    { name: "sparks", hues: rainbow, shake: 1, tear: 0, gravity: 1100, speed: 300, burst: 12, sides: true, floor: false, rain: false, glow: -1 },
    { name: "fire", hues: [0.0, 0.025, 0.05, 0.075, 0.1, 0.13], shake: 0.8, tear: 0, gravity: -900, speed: 160, burst: 14, sides: true, floor: true, rain: false, glow: 0.05 },
    { name: "party", hues: rainbow, shake: 0.5, tear: 0, gravity: 500, speed: 420, burst: 18, sides: false, floor: false, rain: true, glow: -1 },
    { name: "glitch", hues: [0.5, 0.83, 0.33], shake: 1.8, tear: 1, gravity: 0, speed: 520, burst: 8, sides: true, floor: false, rain: false, glow: 0.5 }
  ]
  property int modeIndex: 0
  readonly property var mode: modes[modeIndex]

  // The parts, each with its own switch in the flame's menu: the rattle,
  // the sparks from the caret, the glow and sprays from the edges of the
  // screen, the combo counter, and the guitars.
  property bool shaking: true
  property bool sparks: true
  property bool edges: true
  property bool counter: true

  // The switches and the mode are remembered across restarts of the shell;
  // whether hardcore mode itself is on is not.
  property bool restored: false
  function remember() {
    if (!restored) return
    store.setText(JSON.stringify({
      mode: modes[modeIndex].name, shaking: shaking, sparks: sparks, edges: edges, counter: counter, sound: sound
    }, null, 2) + "\n")
  }
  function restore(text) {
    try {
      var saved = JSON.parse(text || "{}")
      if (saved && typeof saved === "object") {
        if (typeof saved.mode === "string") setMode(saved.mode)
        var flags = ["shaking", "sparks", "edges", "counter", "sound"]
        for (var i = 0; i < flags.length; i++) if (typeof saved[flags[i]] === "boolean") root[flags[i]] = saved[flags[i]]
      }
    } catch (e) {}
    restored = true
  }
  onModeIndexChanged: remember()
  onShakingChanged: { remember(); if (!shaking) clearShader() }
  onSparksChanged: remember()
  onEdgesChanged: remember()
  onCounterChanged: remember()

  FileView {
    id: store
    path: Quickshell.env("HOME") + "/.local/state/omarchy-hardcore.json"
    atomicWrites: true
    printErrors: false
    onLoaded: root.restore(text())
    onLoadFailed: root.restore("")
  }

  // Guitars: every key plays the next note of a riff. The helper plays them
  // itself, so that a note does not wait on the shell; here is only the switch.
  property bool sound: true
  onSoundChanged: { remember(); tellSound() }
  function tellSound() { if (keys.running) keys.write("sound " + (sound ? 1 : 0) + "\n") }

  // The focused window: its monitor, and its rectangle on that monitor in
  // logical pixels. Null until Hyprland has answered, or with nothing focused.
  property var target: null
  // Where the typing happens, as fractions of the window, and when that was
  // last seen. The helper cannot always tell; then sparks land anywhere.
  property var caret: null

  readonly property string dir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  // Hyprland reloads the shader only when the path changes, so two take turns.
  property int slot: 0

  function toggle() { on = !on }
  function nextMode() { modeIndex = (modeIndex + 1) % modes.length }
  function setMode(name) {
    for (var i = 0; i < modes.length; i++) if (modes[i].name === name) { modeIndex = i; return true }
    return false
  }

  // A point in the window to throw sparks from: the caret while it is known.
  function origin() {
    var t = target
    if (!t) return null
    var c = caret
    if (c && Date.now() - c.at < 3000) return { x: t.x + c.x * t.w, y: t.y + c.y * t.h }
    return { x: t.x + Math.random() * t.w, y: t.y + Math.random() * t.h }
  }

  // A screen shader of the user's own, found when hardcore mode is switched
  // on. It is what the rattle gives way to again, rather than to nothing.
  property string ownShader: ""

  // Hyprland takes the shader through `hyprctl eval` with a Lua config and
  // through `hyprctl keyword` with the older one; whichever it speaks.
  readonly property string shaderScript:
    'out=$(hyprctl eval "hl.config({ decoration = { screen_shader = \'$1\' } })" 2>/dev/null); '
    + '[ "$out" = ok ] || hyprctl keyword decoration:screen_shader "${1:-[[EMPTY]]}" >/dev/null 2>&1'

  function clearShader() {
    Quickshell.execDetached(["sh", "-c", shaderScript, "sh", ownShader])
  }

  function num(value) { return Number(value).toFixed(5) }

  function shake() {
    var t = target
    if (!t || !typing || !shaking) return
    // 2 to 7 logical pixels either way, more for a wilder mode and a long streak.
    var strength = mode.shake * (1 + power * 1.5)
    var reach = function() { return (Math.random() < 0.5 ? -1 : 1) * (2 + Math.random() * 5) * strength }
    var tear = mode.tear * (12 + power * 40) * (Math.random() < 0.5 ? -1 : 1)
    var source = "#version 300 es\n"
      + "precision highp float;\n"
      + "in vec2 v_texcoord;\n"
      + "uniform sampler2D tex;\n"
      + "out vec4 fragColor;\n"
      + "const vec2 lo = vec2(" + num(t.x / t.mw) + ", " + num(t.y / t.mh) + ");\n"
      + "const vec2 hi = vec2(" + num((t.x + t.w) / t.mw) + ", " + num((t.y + t.h) / t.mh) + ");\n"
      + "const vec2 jolt = vec2(" + num(reach() / t.mw) + ", " + num(reach() / t.mh) + ");\n"
      + "const vec2 monitor = vec2(" + num(t.pw) + ", " + num(t.ph) + ");\n"
      + "const float tear = " + num(tear / t.mw) + ";\n"
      + "const float seed = " + num(Math.random() * 100) + ";\n"
      + "void main() {\n"
      + "  vec2 uv = v_texcoord;\n"
      + "  vec4 c = texture(tex, uv);\n"
      // Other monitors run this shader too; one of another size is left alone.
      + "  bool here = vec2(textureSize(tex, 0)) == monitor;\n"
      + "  if (here && all(greaterThanEqual(uv, lo)) && all(lessThanEqual(uv, hi))) {\n"
      + "    vec2 at = uv + jolt;\n"
      // Every so many rows, a band of the window is ripped sideways.
      + "    float band = fract(sin(floor(uv.y * 48.0) * 12.9898 + seed) * 43758.5453);\n"
      + "    if (band > 0.8) at.x += tear * (band - 0.8) * 5.0;\n"
      + "    at = clamp(at, lo, hi);\n"
      + "    vec2 split = jolt * 0.5 + vec2(abs(tear) * 0.15, 0.0);\n"
      + "    c = vec4(texture(tex, clamp(at + split, lo, hi)).r, texture(tex, at).g, texture(tex, clamp(at - split, lo, hi)).b, c.a);\n"
      + "  }\n"
      + "  fragColor = c;\n"
      + "}\n"
    slot = 1 - slot
    var path = runtimeDir + "/omarchy-hardcore-" + slot + ".frag"
    Quickshell.execDetached(["sh", "-c", 'printf %s "$2" > "$1" && ' + shaderScript, "sh", path, source])
  }

  onTypingChanged: {
    if (typing) { locate.running = true; shake() }
    else { clearShader(); settles = 0; settle.restart() }
  }
  // A jolt still on its way when the typing stopped can land after the
  // clear and leave the window pushed aside. So the clear is repeated a
  // quarter of a second, one second and three seconds later, by which time
  // nothing can still be under way.
  property int settles: 0
  Timer {
    id: settle
    interval: [250, 750, 2000][root.settles] || 2000
    onTriggered: {
      if (root.typing) return
      root.clearShader()
      root.settles += 1
      if (root.settles < 3) restart()
    }
  }
  onOnChanged: {
    if (on) probe.running = true
    else { typing = false; heat = 0; streak = 0; caret = null }
  }
  Component.onDestruction: clearShader()

  function pulse() {
    streak += 1
    heat = Math.min(1, heat + 0.22)
    beat = (beat + 1) % 1000000
    typing = true
    calm.restart()
    combo.restart()
  }

  // The shake stops this long after the last key.
  Timer { id: calm; interval: 220; onTriggered: root.typing = false }
  // The streak is lost after this long without a key.
  Timer { id: combo; interval: 2500; onTriggered: root.streak = 0 }
  // The overlay stays mapped a little longer, so the sparks can land.
  Timer { id: linger; interval: 2600 }
  onBeatChanged: linger.restart()
  Timer { interval: 40; repeat: true; running: root.heat > 0; onTriggered: root.heat = Math.max(0, root.heat - 0.018) }
  Timer { interval: 45; repeat: true; running: root.typing; onTriggered: root.shake() }
  // Follow the focus while typing goes on.
  Timer { interval: 400; repeat: true; running: root.typing; onTriggered: locate.running = true }

  Process {
    id: keys
    running: root.on
    command: [root.dir + "/bin/keypulse"]
    stdinEnabled: true
    onStarted: root.tellSound()
    stdout: SplitParser {
      onRead: function(line) {
        if (!root.on) return
        if (line === "k") { root.pulse(); return }
        var parts = line.split(" ")
        if (parts.length !== 3 || parts[0] !== "c") return
        var x = Number(parts[1])
        var y = Number(parts[2])
        if (x >= 0 && x <= 1 && y >= 0 && y <= 1) root.caret = { x: x, y: y, at: Date.now() }
      }
    }
  }

  // `omarchy-shell hardcore toggle` for a key binding, `mode` for the next
  // flavour or `mode <name>` for one of them, `sound` for the guitars on or
  // off; `pulse` fakes a key.
  IpcHandler {
    target: "hardcore"

    function toggle(): string { root.toggle(); return root.on ? "on" : "off" }
    function mode(name: string): string {
      if (name === "" || name === "next") root.nextMode()
      else if (!root.setMode(name)) return "unknown mode"
      return root.mode.name
    }
    function sound(): string { root.sound = !root.sound; return root.sound ? "sound on" : "sound off" }
    function pulse(): string { if (root.on) root.pulse(); return root.on ? "ok" : "off" }
  }

  // The screen shader in use before the rattle starts, to put back after.
  Process {
    id: probe
    command: ["hyprctl", "-j", "getoption", "decoration:screen_shader"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var path = String(JSON.parse(text).str || "")
          if (path.indexOf("omarchy-hardcore-") >= 0) return
          // Only a path that can be handed back as it is.
          root.ownShader = path === "[[EMPTY]]" || /['"\\\n]/.test(path) ? "" : path
        } catch (e) {}
      }
    }
  }

  // Where the focused window is. Two JSON documents, one per line.
  Process {
    id: locate
    command: ["sh", "-c", "hyprctl -j activewindow | tr -d '\\n'; echo; hyprctl -j monitors | tr -d '\\n'"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var lines = text.split("\n")
          var win = JSON.parse(lines[0])
          var monitors = JSON.parse(lines[1])
          var mon = null
          for (var i = 0; i < monitors.length; i++) if (monitors[i].id === win.monitor) mon = monitors[i]
          if (!mon || !win.size || !(win.size[0] > 0)) { root.target = null; return }
          var turned = mon.transform % 2 === 1
          var mw = (turned ? mon.height : mon.width) / mon.scale
          var mh = (turned ? mon.width : mon.height) / mon.scale
          var x = Math.max(0, win.at[0] - mon.x)
          var y = Math.max(0, win.at[1] - mon.y)
          root.target = {
            monitor: String(mon.name), mw: mw, mh: mh, pw: mon.width, ph: mon.height,
            x: x, y: y,
            w: Math.min(win.size[0], mw - x), h: Math.min(win.size[1], mh - y)
          }
        } catch (e) {
          root.target = null
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay
      required property var modelData
      readonly property bool here: !!root.target && root.target.monitor === modelData.name

      screen: modelData
      visible: root.on && here && (root.typing || linger.running)
      anchors { top: true; left: true; bottom: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "omarchy-hardcore"
      // Nothing here takes the pointer: clicks fall through to the windows.
      mask: Region {}

      // Hue of the glow and the counter; it turns a little with every key
      // unless the mode keeps to one colour.
      readonly property real hue: root.mode.glow >= 0 ? root.mode.glow : (root.beat * 0.045) % 1

      // Glow down the left and right edges of the screen, as hot as the typing.
      Repeater {
        model: 2

        Rectangle {
          required property int index
          readonly property bool onLeft: index === 0
          width: 70 + root.power * 80
          height: overlay.height
          x: onLeft ? 0 : overlay.width - width
          opacity: root.heat
          visible: root.edges
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: onLeft ? 0 : 1; color: Qt.hsla(overlay.hue, 1, 0.55, 0.5) }
            GradientStop { position: onLeft ? 1 : 0; color: Qt.hsla(overlay.hue, 1, 0.55, 0) }
          }
        }
      }

      ParticleSystem { id: sparks; running: overlay.visible }

      // One set of emitters per colour: a burst from the caret on each key,
      // and whatever the mode pours in from the edges of the screen.
      Repeater {
        model: root.mode.hues

        Item {
          id: colour
          required property int index
          required property real modelData
          readonly property string group: "h" + index
          readonly property int colours: root.mode.hues.length
          anchors.fill: parent

          ImageParticle {
            system: sparks
            groups: [colour.group]
            source: Qt.resolvedUrl("pixel.png")
            color: Qt.hsla(colour.modelData, 1, 0.58, 1)
            colorVariation: 0.15
            entryEffect: ImageParticle.None
          }

          // Chunky pixels thrown out in every direction.
          Emitter {
            id: burst
            system: sparks
            group: colour.group
            enabled: false
            lifeSpan: 750
            lifeSpanVariation: 350
            size: 11 + root.power * 8
            sizeVariation: 7
            endSize: 2
            velocity: AngleDirection { angleVariation: 180; magnitude: root.mode.speed; magnitudeVariation: root.mode.speed * 0.7 }
            acceleration: PointDirection { y: root.mode.gravity }
          }

          Connections {
            target: root
            function onBeatChanged() {
              if (!overlay.here || !root.sparks) return
              var at = root.origin()
              if (!at) return
              // Every 25th key in a row, all the colours go off at once.
              if (root.streak > 0 && root.streak % 25 === 0) { burst.burst(root.mode.burst * 3, at.x, at.y); return }
              // Otherwise two or three of them answer each key.
              if (Math.random() > (2 + root.power) / colour.colours) return
              burst.burst(Math.round(root.mode.burst * (1 + root.power)), at.x, at.y)
            }
          }

          // Sprays inwards from the left and right edges of the screen.
          Repeater {
            model: root.mode.sides && root.edges ? 2 : 0

            Emitter {
              required property int index
              readonly property bool onLeft: index === 0
              system: sparks
              group: colour.group
              x: onLeft ? 0 : overlay.width
              width: 1
              height: overlay.height
              enabled: root.heat > 0.05
              emitRate: root.heat * (360 + root.power * 500) / colour.colours
              lifeSpan: 650
              lifeSpanVariation: 300
              size: 8
              sizeVariation: 5
              endSize: 1
              velocity: AngleDirection { angle: onLeft ? 0 : 180; angleVariation: 40; magnitude: 320 + root.power * 300; magnitudeVariation: 200 }
              acceleration: PointDirection { y: root.mode.gravity * 0.45 }
            }
          }

          // Flames: sparks rising off the bottom edge of the screen.
          Emitter {
            system: sparks
            group: colour.group
            y: overlay.height
            width: overlay.width
            height: 1
            enabled: root.mode.floor && root.edges && root.heat > 0.05
            emitRate: root.heat * (700 + root.power * 900) / colour.colours
            lifeSpan: 900
            lifeSpanVariation: 500
            size: 16
            sizeVariation: 10
            endSize: 1
            velocity: AngleDirection { angle: 270; angleVariation: 18; magnitude: 180 + root.power * 260; magnitudeVariation: 140 }
            acceleration: PointDirection { y: -260 }
          }

          // Confetti: falling from the top edge, drifting sideways.
          Emitter {
            system: sparks
            group: colour.group
            width: overlay.width
            height: 1
            enabled: root.mode.rain && root.edges && root.heat > 0.05
            emitRate: root.heat * (420 + root.power * 600) / colour.colours
            lifeSpan: 2200
            lifeSpanVariation: 600
            size: 10
            sizeVariation: 6
            endSize: 6
            velocity: AngleDirection { angle: 90; angleVariation: 35; magnitude: 260; magnitudeVariation: 160 }
            acceleration: PointDirection { y: 420 }
          }
        }
      }

      // The combo counter, in the top right corner of the window being
      // typed in. It jumps on every key and grows with the streak.
      Text {
        id: counter
        readonly property var t: root.target
        visible: root.counter && root.streak >= 5 && !!t
        textFormat: Text.PlainText
        text: "×" + root.streak
        color: Qt.hsla(overlay.hue, 1, 0.62, 1)
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.75)
        font.pixelSize: 26 + root.power * 54
        font.bold: true
        x: t ? t.x + t.w - width - 24 : 0
        y: t ? t.y + 16 : 0
        transformOrigin: Item.TopRight

        Connections {
          target: root
          function onBeatChanged() { pop.restart() }
        }
        NumberAnimation { id: pop; target: counter; property: "scale"; from: 1.3; to: 1; duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
