# Dependencies

## Required

- C++20 compiler
- CMake 3.24+

## Recommended Geometry Backend

- Open CASCADE Technology

On macOS with Homebrew:

```bash
brew install cmake opencascade
```

Then build:

```bash
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
```

## Why OCCT Is Optional In The Build

The engine must remain buildable on developer machines, CI, Android cross-compilation images, and future cloud workers. For that reason, the public core model does not directly expose OCCT types. OCCT integration should live behind adapters and can be enabled only where the SDK is available.

