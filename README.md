# Multipaste

Copy several things, then paste them one after another.

Copy as usual. Every copy since your last paste is kept in a stack. Then each ⌘V pastes the next one, in the order you copied them. After the last one, ⌘V is ordinary again.

- From the second copy on, a number appears beside the pointer: how many are in the stack.
- The number beside the menu bar icon is how many are still waiting to be pasted.
- ⌃⌘V makes the next ⌘V paste the whole stack at once. Images go over as one paste, so a canvas like Figma can lay them out together and one undo removes them. Text goes over one item per line.
- The next copy after a paste starts a new stack.
- Anything a password manager marks as private is never kept.

## Build

Needs a Mac on macOS 13 or later with Apple's command line tools (`xcode-select --install`).

```
bash build.sh
```

The app is built into `build/` and opened. It lives in the menu bar.

## Permission

None. The app does not watch the keyboard.

After each copy it puts the oldest unpasted copy back on the clipboard as a promise: the formats are listed, but the contents are handed over only when something asks for them. macOS asks at the moment of a paste, and that is how the app knows to line up the next copy.

## Menu

- **Paste All with Next ⌘V** ⌃⌘V. Not offered for a stack that mixes kinds, such as text and images.
- **Clear** empties the stack. ⌘V then pastes the last thing you copied, as it normally would.
- **Open at Login**

## The page

`docs/index.html` is the landing page. GitHub Pages can publish the `docs` folder as a public link. The same page with `#install` on the end of its address shows the install steps.

## Known limits

- Copy two things without pasting in between and the next ⌘V gives the first of them, not the latest. Clear is the way out.
- Anything that reads the clipboard counts as a paste, because the app can't tell who is asking. An app that looks at the clipboard on its own moves the stack on by one.
- Clipboard history tools (Raycast, Maccy, the one in Spotlight) and Multipaste get in each other's way. Multipaste puts every copy back on the clipboard itself, marked so that history tools skip it, and a history tool that checks the clipboard less often than Multipaste does can miss copies while Multipaste is running.
- Two pastes less than about a quarter of a second apart can give the same copy twice.
- An app that keeps a richer copy of its own than the one it puts on the clipboard (Photoshop layers, for example) may fall back to the clipboard's version.
- Pasting some of a stack and then copying something new drops the rest of that stack.
- The ⌃⌘V shortcut assumes a QWERTY layout.
- The stack lives in memory and is gone when the app quits.
