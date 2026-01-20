# PRMaster

A macOS menu bar app for managing GitHub Pull Requests. Quickly see PRs you need to review, track your own PRs, and get notifications for updates.

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools
- GitHub CLI (`gh`) installed and authenticated
- Claude Code (`claude`) or Github Copilot (`copilot`) for AI summary

## Using PRMaster

### Prerequisites

#### Github CLI client

Install and authenticate GitHub CLI before running the app:

```bash
brew install gh
gh auth login
```

#### AI client

Install Claude Code if you want to use `claude` for AI summary
- https://code.claude.com/docs/en/quickstart

Install Gituhub Copilot CLI to use copilot for AI summary
- https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli


Since the app is not signed with an Apple Developer ID, you need to remove the quarantine flag before running:

```bash
xattr -cr /path/to/PRMaster.app
open /path/to/PRMaster.app
```

## Configuration

- `<cmd>+<shift>+p` will open app in windowed mode
- refresh interval: how often we want to pull github for PRs
- startup: do you want to run app on login
- notification: do you want to get notified when you are added as reviewer?
    - notify on filter math: you can optionally enable notification only when certain filter match. This can be helpful if you are only interested in certain type of PR
- notification on your PR: you can enable notification on your PR as well. This will be when someone commented, or added their review feedback. (first visiblity is ignored as it can just be you creating a PR)
- menu label: You can display count of PR on your menu bar
    - You can also add a count of filters you created. This can be super useful if you only care about certain PR

### AI Provider

You can choose betweeen Claude Code or Github Copilot for AI summary.
This app does not store any session or anything, so you need to make sure whatever provider you use, it is properly setup and authenticated.

Token Ratio: This is used for chunking a message we sent to AI for summary. Diff can be large and may not fit. If that happens we chunk it. Default (2) is for code as code can be expensive in terms of tokens.


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
   
4. AI Summary
    - make sure either `claude` or `copilot` is installed and authenticated
    

## Building

Clone the repository and run the build script:

```bash
git clone https://github.com/seg4lt/prmaster.git
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

Download the latest universal binary (arm64 + x86_64) from [Releases](https://github.com/seg4lt/prmaster/releases).


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
