# PRMaster

A macOS menu bar app for managing GitHub Pull Requests. Quickly see PRs you need to review, track your own PRs, and get notifications for updates.

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools
- GitHub CLI (`gh`) installed and authenticated

## Setup

1. Install Xcode Command Line Tools:
   ```bash
   xcode-select --install
   ```

2. Install GitHub CLI:
   ```bash
   brew install gh
   ```

3. Authenticate with GitHub:
   ```bash
   gh auth login
   ```

## Building

Clone the repository and run the build script:

```bash
git clone https://github.com/yourusername/prmaster.git
cd prmaster
./build-app.sh
```

The app bundle will be created at `.build/release/PRMaster.app`.

## Running

After building:

```bash
open .build/release/PRMaster.app
```

Or install to Applications:

```bash
cp -r .build/release/PRMaster.app /Applications/
```

## Download

Download the latest universal binary (arm64 + x86_64) from [Releases](https://github.com/yourusername/prmaster/releases).

Since the app is not signed with an Apple Developer ID, you need to remove the quarantine flag before running:

```bash
xattr -cr /path/to/PRMaster.app
open /path/to/PRMaster.app
```

## Creating a Release

To create a new release, push a version tag from the main branch:

```bash
git checkout main
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will automatically build a universal macOS app (arm64 + x86_64) and attach it to the release.

## Features

- Menu bar icon with PR count badge
- View PRs awaiting your review
- Track PRs you've already reviewed
- See your own open PRs
- Desktop notifications for PR updates
- Global hotkey (Option+Command+Shift+P) to open full window
- Custom filters for notifications

## Data Storage

App data is stored at:
```
~/Library/Application Support/PRMaster/
```

