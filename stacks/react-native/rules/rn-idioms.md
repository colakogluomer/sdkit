# React Native idioms

Rules that hold for any React Native app (bare or Expo, TypeScript or JavaScript). Navigation structure, state library and
design system belong in the project's own rules.

## Rendering and lists

- Long or unbounded lists use `FlatList` or `FlashList`, never `ScrollView` + `map`. Always give a stable `keyExtractor`
  (a domain id, never the index).
- Keep hot render paths cheap: no inline functions or object/array literals passed to list items; hoist styles to
  `StyleSheet.create`, extract the row into its own component.
- Memoize (`memo`, `useCallback`, `useMemo`) where a profile shows a cost, not by default.
- Heavy work (parsing, sorting big arrays, crypto) stays off the JS thread: defer with `InteractionManager`, move to a
  native module or worklet. Animations use the native driver or Reanimated.

## Platform

- Platform differences go through `Platform.select` or `.ios.tsx` / `.android.tsx` files, not scattered `Platform.OS` checks.
- Respect safe areas (`react-native-safe-area-context`) and the keyboard (`KeyboardAvoidingView` or a keyboard-aware list).
- Ask for permissions at the point of use, with a rationale, and handle denial and "never ask again".

## Security and data

- The bundle is client code: no secrets, API keys with write power or private URLs in it. Tokens go in the secure store
  (Keychain/Keystore), not `AsyncStorage`.
- Never log tokens or personal data; strip `console.*` from release builds.

## Accessibility and navigation

- Interactive elements carry `accessibilityRole` and an `accessibilityLabel` when the visible text is not enough.
  Touch targets are at least 44x44 pt.
- Type the navigation params (route param list) and use the typed hooks; no `any` routes.

## Native and runtime

- A change to a native module, `ios/`, `android/` or app config needs a rebuild and a manual check on a device or
  simulator; `verify` does not cover it.
- New `react-native-*` dependencies with native code need a dev client rebuild (Expo) or `pod install` / Gradle sync (bare).
- Check Hermes and New Architecture (Fabric/TurboModules) compatibility before adding a native library.
