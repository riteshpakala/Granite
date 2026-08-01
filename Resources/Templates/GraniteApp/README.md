# __DISPLAY_NAME__

A shared iOS, iPadOS, and macOS SwiftUI application powered by Granite.

## Structure

```text
Shared/
├── App.swift
├── Assets.xcassets
├── Components/
│   ├── Home/
│   └── Settings/
├── Services/
│   ├── Config/
│   │   ├── Config.swift
│   │   └── Config+Center.swift
│   └── Environment/
│       ├── Environment.swift
│       └── Environment+Center.swift
├── Utilities/
│   └── Extensions/
└── Views/
iOS/
└── PlatformNavigationView.swift
macOS/
└── PlatformNavigationView.swift
```

`Home.swift`, `Home+View.swift`, and `Home+Center.swift` define `HomeComponent`; Settings follows
the same convention. `Environment.swift` and `Environment+Center.swift` define
`EnvironmentService`, while Config follows the same service convention without a `+View` file.

`EnvironmentService` owns application boot state. `ConfigService` owns persisted settings and
the lightweight usage cache. `HomeComponent` selects native tab navigation on compact iOS and
native sidebar navigation on iPad and macOS. Add new Swift files beneath one of the synchronized
source folders and Xcode includes them automatically.

The Xcode project uses the Granite Swift package at `__GRANITE_PATH__`. When generated with
`--copy-granite`, the package lives at `Packages/Granite` and moves with this app. Otherwise, if
the linked checkout moves, update the local package reference in Xcode. Add an AppIcon asset and
choose your development team before archiving for distribution.
