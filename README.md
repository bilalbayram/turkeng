# turkeng

A macOS menu bar app for instant Turkish ↔ English translation — with ghost text autocomplete and keyboard-first navigation.

<p align="center">
  <img src="assets/demo.gif" alt="turkeng — Turkish ↔ English translator in action" width="820" />
</p>

## What it does

turkeng lives in your menu bar and gives you a fast, keyboard-driven translation panel. Hit **⌥T** from anywhere, type your text, and get translations instantly — no browser tabs, no copy-pasting between apps.

**Auto Language Detection** — Uses Apple's NaturalLanguage framework to detect whether you're typing Turkish or English and sets the translation direction automatically.

**Ghost Text Autocomplete** — As you type, translucent suggestions appear based on your query history and a seed dictionary of common phrases. Press **Tab** or **→** to accept.

**Multiple Matches** — Returns up to 5 translation matches from MyMemory translation memory, ranked by confidence score. Navigate with **↑↓** and hit **Enter** to copy.

## Install

Download the latest `.dmg` from [GitHub Releases](../../releases) and drag to Applications.

The app runs in the menu bar — no dock icon, no clutter. Press **⌥T** (Option+T) to open the translator.

## Development

Built with Swift + SwiftUI, managed by [Tuist](https://tuist.io). Requires macOS 14.0+.

```bash
tuist install
tuist generate
open turkeng.xcworkspace
```
