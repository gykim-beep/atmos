# Bug Analysis & Rules Phase 2: Riverpod `ref.read` vs `ref.watch`

## 1. Issue Description
In Phase 1, although state management was refactored and updated properly using Riverpod, adding an audio file to a room in the UI did not instantly reflect on the main screen. The list of audio files would not re-render immediately (Zero-delay) despite the internal state being correctly updated.

## 2. Root Cause Analysis
The root cause was the incorrect use of Riverpod's state reading mechanism inside the `build` method of `RoomCard`.

- **`ref.read`:** This is a one-time read mechanism. When used inside a `build` method, it retrieves the current state of a provider but **does not** create a subscription to it. Therefore, when the `configProvider` state changed (e.g., a new track was added), the widget did not know it needed to rebuild.
- **`ref.watch`:** This method retrieves the current state of a provider and **creates a reactive subscription**. Whenever the state of `configProvider` changes, any widget that called `ref.watch(configProvider)` is automatically marked as dirty and its `build` method is triggered again.

Because `ref.read(configProvider)` was used in the `RoomCard`'s `build` method, the addition of new audio tracks modified the global state but failed to trigger the UI rebuild necessary to display the new tracks immediately.

## 3. Resolution
The code in `lib/features/dashboard/widgets/room_card.dart` was updated:
```diff
- final AppConfig? config = ref.read(configProvider);
+ final AppConfig? config = ref.watch(configProvider);
```
By switching to `ref.watch`, `RoomCard` now actively listens to `configProvider`. Any changes (like adding or deleting tracks) will now instantly rebuild the UI and reflect the state changes with zero delay.

## 4. Rule Established
**Never use `ref.read` inside a Flutter `build` method for state that dictates UI rendering.**
- Use `ref.watch` inside `build()` to reactively rebuild the UI upon state changes.
- Use `ref.read` **only** inside event handlers, callbacks (e.g., `onPressed`), or `initState` where you need a one-time execution without a reactive subscription.
