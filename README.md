# Multipaste

Copy several things, then paste them one after another.

Copy as usual. Every copy since your last paste is kept in a stack. Then each ⌘V pastes the next one, in the order you copied them. After the last one, ⌘V is ordinary again.

- From the second copy on, a number appears beside the pointer: how many are in the stack.
- The number beside the menu bar icon is how many are still waiting to be pasted.
- ⌃⌘V pastes the whole stack at once. Images go over as one paste, so a canvas like Figma can lay them out together and one undo removes them. Text goes over one item per line.
- The next copy after a paste starts a new stack.
- Anything a password manager marks as private is never kept.

## Build

Needs a Mac on macOS 13 or later with Apple's command line tools (`xcode-select --install`).

```
bash build.sh
```

The app is built into `build/` and opened. It lives in the menu bar.

## Permission

macOS asks for Accessibility the first time. The app needs it to see ⌘V a moment before the app in front does, so it can put the right copy on the clipboard. Allow it in System Settings → Privacy & Security → Accessibility.

A build you make yourself gets a new signature every time, so after rebuilding, remove the old entry from that list and allow the new one.

## Menu

- **Paste All** ⌃⌘V
- **Clear** empties the stack. ⌘V then pastes the last thing you copied, as it normally would.
- **Open at Login**

## The page

`docs/index.html` is the landing page. GitHub Pages can publish the `docs` folder as a public link. The same page with `#install` on the end of its address shows the install steps.

## Known limits

- Copy two things without pasting in between and the next ⌘V gives the first of them, not the latest. Clear is the way out.
- A paste chosen from a menu (Edit → Paste, or right-click → Paste) isn't seen, so it pastes the last thing copied and the stack doesn't move on.
- Pasting some of a stack and then copying something new drops the rest of that stack.
- The shortcuts assume a QWERTY layout.
- The stack lives in memory and is gone when the app quits.
