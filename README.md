# sesh-bar

Native macOS menu-bar switcher for AWS SSO accounts and roles — the fastest way to change which AWS account your terminal talks to.

Built on the same on-disk state as [`awsesh`](https://github.com/elva-labs/awsesh): sessions, cached tokens, preferred roles, and `~/.aws/credentials` are fully shared, so the CLI and the menu bar stay in sync. No CLI dependency — SSO device-code login, account/role listing, and credential fetch run natively via the AWS SDK for Swift.

## Features

- Menu-bar title shows the **active account**; popover lists accounts grouped by SSO session, with search across accounts, roles, and sessions
- One click switches your **default AWS profile** (role and region fall back to your remembered preferences); right-click for other roles
- Give each SSO session its own **CLI profile** (default `default`) to keep several sessions active at once — pick one per terminal with `AWS_PROFILE`
- **Starred accounts** pinned on top; token-expiry indicators per session and for the active credential
- Sign in via the standard **SSO device-code browser flow**; sign out and session management (add/edit/remove) in Settings
- Open the AWS console for the active account from the menu

## Install

Build from source (macOS 13+, Xcode 15+):

```sh
git clone https://github.com/elva-labs/sesh-bar.git
cd sesh-bar
make app     # builds build/sesh-bar.app
make run
```

A signed/notarized release and a Homebrew cask (`elva-labs/elva`) are on the way.

## Architecture

- `AwseshCore` — Swift port of [`@awsesh/core`](https://github.com/elva-labs/awsesh): byte-format-compatible storage (`~/.config/awsesh`, `~/.local/share/awsesh`, `~/.aws/credentials`) plus SSO/SSO-OIDC via AWS SDK for Swift. Fully unit-tested, including an opt-in `AWSESH_REAL=1` suite against real files.
- `SeshBar` — AppKit status item + SwiftUI popover/settings.

## License

[MIT](LICENSE) © Elva Group AB
