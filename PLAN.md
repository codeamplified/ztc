# Plan to Implement Scrolling in TUI

## 1. Introduce a Viewport Component

- **Action:** Add the `viewport` component from the `bubbletea` library to the project.
- **File to Modify:** `tui/go.mod`
- **Details:** The `viewport` is essential for handling scrollable content. I will add it as a dependency.

## 2. Integrate Viewport into the `ConfigModel`

- **Action:** Add a `viewport` field to the `ConfigModel` struct.
- **File to Modify:** `tui/models/config.go`
- **Details:**
    - The `viewport` will be initialized in the `NewConfigModel` function.
    - The `Update` method will be updated to handle scrolling key presses and update the viewport's position.
    - The `View` method will be changed to render its content through the viewport.

## 3. Refactor `renderCurrentStep`

- **Action:** Modify the `renderCurrentStep` function to render its content into the viewport.
- **File to Modify:** `tui/models/config.go`
- **Details:** Instead of returning a string to be rendered directly, the content will be set as the viewport's content.

## 4. Ensure Proper Sizing

- **Action:** The viewport's size will be dynamically updated when the terminal window is resized.
- **File to Modify:** `tui/models/config.go`
- **Details:** The `WindowSizeMsg` case in the `Update` method will be used to set the viewport's width and height.

## 5. Add Scrolling to `WelcomeModel`

- **Action:** Add a viewport to the `WelcomeModel` to make the template selection scrollable.
- **File to Modify:** `tui/models/welcome.go`
- **Details:** This will be particularly useful for the "Advanced" template view, which can have a long list of templates. The implementation will be similar to the changes in `ConfigModel`.
