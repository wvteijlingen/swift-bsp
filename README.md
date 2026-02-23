# Swift Build Server

Swift BSP is a *Build Server Protocol* implementation that serves as a bridge between sourcekit-lsp
(Swift's official Language Server Protocol) and your Xcode project.

With Swift BSP you can **develop for Apple platforms like iOS in any IDE that has support for LSPs**,
such as Cursor and VSCode.

## Installation

```
brew install wvteijlingen/tap/swift-bsp
```

## Usage

### VS Code / Cursor

1. Install the official [Swift](https://marketplace.visualstudio.com/items?itemName=swiftlang.swift-vscode) extension.
1. Create a `buildServer.json` file in the root of your project.
1. Copy the snippet below. If needed, change the `argv` and `swiftBSP` fields.
1. Restart the Swift language server (`Cmd+Shift+P -> Swift: Restart LSP Server`) or reload the entire window
(`Cmd+Shift+P -> Reload Window`).

> [!IMPORTANT]
> The value for `argv` must point to the `swift-bsp` binary on your system. If the binary is in your `$PATH`,
> for example when using Homebrew, you can simply use `swift-bsp`. Otherwise provide the full path.

```json
{
  "name": "swift-bsp",
  "version": "0.0.1",
  "bspVersion": "2.2.0",
  "languages": ["swift"],
  "argv": ["swift-bsp"]

  // Optional configuration, not needed for most projects
  //
  // "swiftBSP": {
  //   "runDestination": {
  //     "sdk": "...",
  //     "platform": "...",
  //   },
  //   "configuration": "...",
  //   "project": "...",
  //   "verboseLogging": true
  // }
}
```

## Configuration

The following properties are configurable under the `swiftBSP` field in `buildServer.json`:

- `runDestination.sdk`: The name of the SDK to use. Run `xcodebuild -showsdks` to show SDKs installed on your system.
You can omit the version number. For example: `iphonesimulator`.
- `runDestination.platform`: The name of the platform to use.
Valid values are: `macosx|iphonesimulator|iphoneos|appletvsimulator|appletvos|watchsimulator|watchos|xrsimulator|xros`.
- `configuration`: The name of the Xcode configuration to use for indexing and building. Defaults to `Debug`.
- `project`: The name of the `.xcproject` or `.xcworkspace` file.
Only needed when there are multiple Xcode projects or workspaces in the same directory.
- `verboseLogging`: When set to `true`, a verbose log file will be created in `build/swift-bsp.log`.
Defaults to `false.`

## Troubleshooting

Swift BSP uses the macOS unified logging system. To see logs, open Console.app and filter on 
`subsystem:nl.wardvanteijlingen.swift-bsp`.

To see the JSONRPC messages that are sent between sourcekit-lsp and swift-bsp, set the `verboseLogging` field in
`buildServer.json` to `true` and restart the language server. This will write all incoming and outgoing messages
to `build/swift-bsp.log`.

**Common issues**

- The `configuration` field in `buildServer.json` is not set to a valid Xcode configuration.
The default value is `Debug`, but the Xcode project might use custom configurations.
- The `runDestination` field in `buildServer.json` is not set to a valid run destination.
When not set, Swift BSP tries to determine a valid run destination, but this heuristic may fail
or result in a destination that is not appropriate for the Xcode project.
