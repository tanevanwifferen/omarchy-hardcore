# Hardcore mode for Omarchy

A gimmick for the [Omarchy](https://omarchy.org) shell. Switch it on with the
flame in the bar, and typing sets things off:

- the window you type in **shakes**, with its colours pulled apart;
- **sparks** fly out of the text cursor;
- the **edges of the screen** glow and spray sparks inwards;
- a **combo counter** climbs for as long as you keep typing, and winds
  everything up as it goes;
- **metal guitar**: every key plays the next note of a riff, so your typing
  sets the tempo. Every 25th key in a row gets a squeal on top.

Stop typing and it all stops.

> **Warning:** this flashes and shakes the screen on purpose. Do not use it if
> you are sensitive to flashing or fast-moving images.

## Install

```bash
omarchy plugin add https://github.com/tanevanwifferen/omarchy-hardcore.git --enable --yes
```

The flame appears in the bar. Hardcore mode is off until you click it, and off
again after every restart of the shell.

## Use

| On the flame | Does |
|---|---|
| Click | Hardcore mode on or off |
| Right click | A menu with the mode and a switch for each part |

The menu has four modes:

- **Sparks**: rainbow sparks that fall.
- **Fire**: flames rising off the bottom of the screen.
- **Party**: confetti from the top, a gentler shake.
- **Glitch**: a harder shake that rips strips of the window sideways.

and a switch each for the shake, the sparks, the screen edges, the combo
counter and the guitars. The mode and the switches are remembered in
`~/.local/state/omarchy-hardcore.json`.

For a key binding or a script:

```bash
omarchy-shell hardcore toggle        # on or off
omarchy-shell hardcore mode fire     # sparks, fire, party, glitch, or next
omarchy-shell hardcore sound         # guitars on or off
```

## What it needs

- **Hyprland.** The shake is a screen shader, set only while keys are being
  hit and taken away when they stop. A screen shader of your own is put back
  afterwards. No file of your configuration is changed.
- **The `input` group**, to notice key presses (`groups` lists it on a stock
  Omarchy install).
- **Python 3 with numpy** (`python-numpy`) for the guitars and for finding the
  text cursor. Without numpy you still get the shake and the sparks.
- **PipeWire** (`pw-cat`) for the guitars.
- **grim 1.5 or newer**, for finding the text cursor.

Nothing is compiled, downloaded or installed, and nothing needs root.

## What it reads, and what it does with it

Hardcore mode has to know *that* you are typing and *where*. Both stay on your
machine: the plugin makes no network connection and writes nothing but its own
settings file.

- **Key presses.** While hardcore mode is on, `bin/keypulse` reads the keyboard
  devices in `/dev/input`. It passes on only the fact that a key went down:
  which key it was is thrown away on the spot, never stored and never sent
  anywhere. The helper does not run while hardcore mode is off.
- **The text cursor.** After a key press it takes a picture of the focused
  window (`grim -T`), compares it with the one from the key before, and takes
  the small patch that changed as the place you are typing at. The pictures
  are compared in memory and dropped; none is written to disk.

Finding the cursor this way works in terminals and ordinary text fields. It
gives up in windows where the picture keeps changing by itself (a video call),
and the sparks then land anywhere in the window.

## Sound

The guitar is not sampled: `bin/riffgen` synthesises every note (a plucked
string model, doubled, through a clipping amplifier and a speaker filter) into
`sounds/`. The files are in the repository, so you only run it to change the
sound, and then it wants `python-scipy` as well.

Notes are mixed into one open stream with a 5 ms buffer, so they follow the
keys closely on wired speakers. Bluetooth headphones add their own delay.

## Remove

```bash
omarchy plugin remove io.github.tanevanwifferen.hardcore --yes
rm -f ~/.local/state/omarchy-hardcore.json
```

## Changing it

A change to `Service.qml` shows up after `omarchy restart shell`; the other
files reload when saved. The modes are a table at the top of `Service.qml`.

## License

MIT, see [LICENSE](LICENSE).
