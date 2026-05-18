fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios deploy

```sh
[bundle exec] fastlane ios deploy
```

TestFlight 배포

### ios diagnose

```sh
[bundle exec] fastlane ios diagnose
```

ASC 의 현재 edit version 상태 + 빌드 진단

### ios check_metadata

```sh
[bundle exec] fastlane ios check_metadata
```

ASC 에 등록된 메타데이터(locale 포함) 다운로드 — 디버그용

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

App Store 심사 제출 (TestFlight 에 이미 업로드된 빌드 사용)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
