<p>
  <img src="images/lostty/mascot-waving.png" alt="Lostty's mascot, a pink axolotl with terminal-prompt eyes, waving hello" width="200">
</p>

# Lostty — Leave Your Desk, Not Your Terminal

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platforms: macOS and iOS](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS-lightgrey)](#getting-started)

The terminal I use every day to run Claude Code and Codex — on my Mac, and on my iPhone when I walk away from it.

Coding agents work best when you let them run. The trouble is, they don't run for long before they need you. They stop to ask for permission, or to ask a question, and then they wait. If you've stepped away, they wait for a long time.

Screen sharing puts a tiny Mac on your phone that you have to pinch and squint at. A plain SSH app gets you a shell, but no idea which of your ten terminals actually needs you.

Lostty is a fast, native Mac terminal with an iPhone app built for exactly this. Every terminal keeps running on your Mac. Your phone shows you which one needs you, and you answer it right there. Then the phone goes back in your pocket.

<p>
  <img src="images/lostty/phone-terminals.png" alt="The Lostty iPhone app listing four terminals: one waiting on you, one with Claude working, one ready and one idle" width="280">
  &nbsp;&nbsp;
  <img src="images/lostty/phone-welcome.png" alt="The Lostty iPhone app's welcome screen: three steps to pair with your Mac" width="280">
</p>

## Getting Started

### 1. Build and install the Mac app

<details>
<summary><strong>What you'll need</strong></summary>

- Xcode 26
- Zig 0.15 and tmux: `brew install zig@0.15 tmux`

</details>

```sh
macos/install-skins.sh
```

This builds Lostty and puts it in `/Applications`. Run it again whenever you pull. It keeps the build it replaced, in case you want to go back.

### 2. Put Lostty on your iPhone

Open `macos/Lostty.xcodeproj` in Xcode, pick the `Lostty-iOS` scheme and your phone, and press Run. If Xcode complains about signing, pick your own team under **Signing & Capabilities**.

### 3. Pair them

Install [Tailscale](https://tailscale.com) on your Mac and your iPhone, signed in to the same account. Then, on the Mac, open **Lostty → Phone Access**. It checks that everything's ready and shows you a QR code. Scan it with your phone.

<details>
<summary><strong>Why Tailscale?</strong></summary>

Your phone talks to your Mac directly, over SSH, inside your own private Tailscale network. There's no Lostty server in the middle. There isn't one. And the phone's SSH key never leaves the phone.

If you'd rather set up the Mac by hand, the steps Phone Access automates are in [docs/lostty-mobile-host-setup.md](docs/lostty-mobile-host-setup.md).

</details>

### 4. That's it. Go take a walk.

## Why Lostty Exists

I built Lostty to fix the things that kept going wrong whenever I left an agent running and walked away.

### #1: The Agent Stopped, And I Didn't Know

**The Problem**: You start Claude on something big. You go make a coffee. Twenty minutes later you come back, and it's been sitting on a permission prompt for nineteen of them.

**The Fix**: Lostty knows what every terminal is doing. Your phone sorts them into **Waiting on you**, **Working**, **Ready** and **Idle**, so the one that needs you is always first. Tap in, answer, and Claude carries on. Anything that waited on you while you were busy lands in the inbox under the bell.

The axolotl tells you at a glance, too. It has a prompt for eyes (`>` and a blinking `—` cursor):

<table>
  <tr>
    <td align="center"><img src="images/lostty/mascot-waiting-on-you.png" alt="The axolotl waving for attention" width="110"><br><sub>Waiting on you</sub></td>
    <td align="center"><img src="images/lostty/mascot-ready.png" alt="The axolotl standing ready" width="110"><br><sub>Ready</sub></td>
    <td align="center"><img src="images/lostty/mascot-sleeping.png" alt="The axolotl asleep" width="110"><br><sub>Idle</sub></td>
  </tr>
</table>

### #2: My Phone Got A Tiny, Useless Mac

**The Problem**: Screen sharing works, technically. But you're pinching around a 27-inch screen on a 6-inch phone, and typing into it is miserable.

**The Fix**: Lostty's phone app is a real terminal. It opens the same session that's running on your Mac: same output, same prompt, same half-typed command. Come back to your Mac and carry on. Nothing restarts.

The keyboard is made for it, too. A tap that lands in the gap between two keys types the nearest one, instead of nothing.

> [!TIP]
> Turn on **Stay Awake** in Lostty's menu bar before you leave:
>
> - Your Mac **keeps working with the lid closed**, even on battery
> - If its Wi-Fi drops, it **hops onto your iPhone's hotspot**, so you can still reach it

### #3: Ten Terminals, All The Same Black Box

**The Problem**: Once you've got a few agents going, every terminal looks the same. Sooner or later, you type into the wrong one.

**The Fix** is skins. Each project gets its own colors and texture, and the terminal changes to match when you move into a project. Pick from twelve built-in skins, or make your own. Your phone shows the same colors, so the list reads at a glance.

Each terminal also says what Claude is doing right now, in plain words, like _Editing App.swift_, with its live _✳ Working…_ line. And a soft glow traces the window while Claude works, so you can tell from across the room.

### #4: Starting Anything Meant Going Back To My Desk

**The Problem**: You're out, and you think of the next thing. Now you either wait until you're back, or you go back.

**The Fix**: Tap **+** on your phone and pick a project folder on your Mac (browse for it, or search). Choose what starts there: Claude, Codex or a plain shell, and which model. It opens on your Mac and on your phone at the same time.

### Summary

Agents are good enough now to keep working while you're gone. Lostty is my attempt at making "gone" actually work: you leave, and your terminals come with you. Enjoy.

## Built On Ghostty

Lostty started from [Ghostty](https://ghostty.org), the fast, native terminal by Mitchell Hashimoto and the Ghostty contributors. Every character you see is drawn by Ghostty's engine, which does the hard part quickly and correctly. Lostty adds the Mac and iPhone side on top.

If you love how fast Lostty feels, that's Ghostty. Go give it a star.

## Reference

- **[HACKING.md](HACKING.md)**: Build, test and debug Lostty. Start here if you want to change something.
- **[SKINS.md](SKINS.md)**: The twelve built-in skins, project skins, and how to make your own.
- **[Lostty on your iPhone](docs/lostty-mobile-phone-access.md)**: How pairing works, and what Phone Access sets up on your Mac.
- **[Manual Mac setup](docs/lostty-mobile-host-setup.md)**: The steps Phone Access automates, for setting up by hand.
- **[UPGRADING.md](UPGRADING.md)**: Merging a new Ghostty release into Lostty.
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Reporting bugs and sending changes.

## License

MIT, like Ghostty before it. See [LICENSE](LICENSE).
