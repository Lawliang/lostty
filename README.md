<p>
  <img src="images/lostty/mascot-sleeping.png" alt="Lostty's mascot, a pink axolotl, fast asleep" width="200">
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

**You'll need:** a Mac on macOS 15 or later, an iPhone on iOS 17 or later with its cable, and a free [Apple Account](https://account.apple.com).

### On your Mac

<details>
<summary><strong>1. Install Xcode 26</strong></summary>

Get it from the [App Store](https://apps.apple.com/app/xcode/id497799835) and open it once. You'll also need [Homebrew](https://brew.sh).

</details>

<details>
<summary><strong>2. Install Lostty</strong></summary>

In Terminal:

```sh
git clone https://github.com/Lawliang/lostty.git
cd lostty
macos/setup.sh
```

It installs what the build needs (it may ask for your password), then builds Lostty, puts it in `/Applications` and opens it. The first build takes a while.

**Updating later:** `git pull`, then `macos/install.sh`, then choose **Restart to Update** in Lostty's menu bar. Don't Quit Lostty to update: quitting ends every terminal session.

</details>

### On your iPhone

<details>
<summary><strong>3. Add your Apple Account to Xcode</strong></summary>

In Xcode: **Settings → Accounts**, click **+**, and sign in.

</details>

<details>
<summary><strong>4. Install the app</strong></summary>

Plug your iPhone into the Mac, unlock it, and tap **Trust**. Then, in the `lostty` folder:

```sh
macos/install-phone.sh
```

The first time, the phone may ask you to:

- turn on **Settings → Privacy & Security → Developer Mode** (the phone restarts);
- trust your Apple Account in **Settings → General → VPN & Device Management**.

Then run the command again.

**With a free Apple Account,** the app stops opening after 7 days. Run the command again to renew it. A paid developer account makes it last a year.

</details>

### Pair them

<details>
<summary><strong>5. Install Tailscale on both</strong></summary>

Install [Tailscale](https://tailscale.com/download) on the Mac and the iPhone, and sign in to both with the same account.

**Why Tailscale?** Your phone talks to your Mac directly, over SSH, inside your own private Tailscale network. There's no Lostty server in the middle. There isn't one. And the phone's SSH key never leaves the phone.

</details>

<details>
<summary><strong>6. Pair</strong></summary>

On the Mac, open **Lostty → Phone Access…** and fix any row without a ✓. Each row says what to click. Then click **Pair a Phone…**, and on the iPhone open Lostty, tap **Pair with Mac** and scan the code. Click **Allow** on the Mac.

If you'd rather set up the Mac by hand, the steps Phone Access automates are in [docs/lostty-mobile-host-setup.md](docs/lostty-mobile-host-setup.md).

</details>

### That's it. Go take a walk.

Your phone reaches the Mac while it's awake and Lostty is open. To keep it reachable with the lid closed, see [Lostty on your iPhone](docs/lostty-mobile-phone-access.md).

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

- **[SKINS.md](SKINS.md)**: The twelve built-in skins, project skins, and how to make your own.
- **[Lostty on your iPhone](docs/lostty-mobile-phone-access.md)**: How pairing works, and what Phone Access sets up on your Mac.
- **[Manual Mac setup](docs/lostty-mobile-host-setup.md)**: The steps Phone Access automates, for setting up by hand.
- **[UPGRADING.md](UPGRADING.md)**: Merging a new Ghostty release into Lostty.
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Build, test and debug Lostty, report bugs and send changes. Start here if you want to change something.

## License

MIT, like Ghostty before it. See [LICENSE](LICENSE).
