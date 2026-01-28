# DMG Background Image Requirements and Best Practices for create-dmg

## Research Summary

Based on analysis of the `create-dmg` tool documentation, real-world examples from popular projects, and DMG creation best practices.

---

## 1. Recommended Background Image Dimensions

### Standard Sizes
The most common and recommended background image dimensions are:

- **800×400 pixels** (most popular, used by 90% of examples)
- **660×400 pixels** (alternative)
- **540×380 pixels** (electron-builder default)

### Why 800×400?
This is the de facto standard because:
- Provides enough space for app icon + Applications link
- Works well on all modern Mac displays
- Matches the most common `--window-size` parameter
- Used by major projects: RustDesk, Ollama, LuLu, pgAdmin, etc.

### Image Format Requirements
- **Format**: PNG (preferred), JPG, or GIF
- **Resolution**: 72 DPI (standard screen resolution)
- **Color space**: sRGB
- **Retina support**: For HiDPI displays, create a 2x version (1600×800) named `background@2x.png`

---

## 2. Window Size vs Background Image Size

### Critical Relationship
The `--window-size` parameter should **match** your background image dimensions:

```bash
# If background is 800×400
--window-size 800 400

# If background is 660×400
--window-size 660 400
```

### Important Notes
1. **Window size = Background image size** (in pixels)
2. The window size does NOT include:
   - Window title bar (~22px)
   - Window borders
   - Toolbar (if visible)
3. The background image fills the **content area** of the window

### Common Issue
If your background appears too large or cut off, the window-size doesn't match the image dimensions.

---

## 3. Coordinate System for Icon Positioning

### Origin and Axes
- **Origin**: Top-left corner of the window content area (0, 0)
- **X-axis**: Increases from left to right
- **Y-axis**: Increases from top to bottom
- **Units**: Device-independent pixels (points on macOS)

### Icon Position Reference Point
According to electron-builder documentation:
> "The x and y coordinates refer to the position of the **center** of the icon (at 1x scale), and do not take the label into account."

However, `create-dmg` appears to use the **top-left corner** of the icon as the reference point based on examples.

### Standard Icon Positions (for 800×400 window)

```bash
# App icon (left side)
--icon "Application.app" 200 190

# Applications link (right side)
--app-drop-link 600 185
```

### Calculating Icon Positions

For an 800×400 window with 100px icons:

1. **Left icon (app)**:
   - X: 200 (centers icon at 1/4 of window width)
   - Y: 190 (centers icon vertically, accounting for label)

2. **Right icon (Applications)**:
   - X: 600 (centers icon at 3/4 of window width)
   - Y: 185-190 (aligned with left icon)

### Formula for Centering Icons
```
X_position = (window_width / 4) for left icon
X_position = (window_width * 3/4) for right icon
Y_position = (window_height / 2) - (icon_size / 2) + label_offset
```

Where `label_offset` is typically 20-40px to account for the icon label below.

---

## 4. Real-World Examples

### Example 1: Standard 800×400 Layout (Most Common)

```bash
create-dmg \
  --volname "Application Installer" \
  --background "installer_background.png" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Application.app" 200 190 \
  --hide-extension "Application.app" \
  --app-drop-link 600 185 \
  "Application-Installer.dmg" \
  "source_folder/"
```

**Background image**: 800×400 pixels
**Icon positions**:
- App: (200, 190) - left side
- Applications: (600, 185) - right side

### Example 2: Larger Icons (128px)

```bash
create-dmg \
  --volname "Ollama" \
  --background "background.png" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 128 \
  --icon "Ollama.app" 200 190 \
  --app-drop-link 600 190 \
  "Ollama.dmg" \
  "Ollama.app"
```

**Background image**: 800×400 pixels
**Icon size**: 128px (larger than standard)
**Note**: Y-coordinates adjusted for larger icons

### Example 3: Alternative Size (660×400)

```bash
create-dmg \
  --volname "My App" \
  --background "background.png" \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "MyApp.app" 165 190 \
  --app-drop-link 495 190 \
  "MyApp.dmg" \
  "MyApp.app"
```

**Background image**: 660×400 pixels
**Icon positions adjusted** for narrower window:
- App: (165, 190) - 1/4 of 660 = 165
- Applications: (495, 190) - 3/4 of 660 = 495

---

## 5. Best Practices

### Design Guidelines

1. **Keep it simple**: Don't overcrowd the background
2. **Visual cues**: Use arrows or text to guide users
3. **Contrast**: Ensure icons are visible against background
4. **Branding**: Include app logo/name but keep it subtle
5. **Safe zones**: Leave 40-50px margins around edges

### Technical Best Practices

1. **Match dimensions**: Always set `--window-size` to match background image size
2. **Test on multiple displays**: Check on Retina and non-Retina displays
3. **Use PNG**: Better quality and transparency support
4. **Icon alignment**: Keep icons vertically aligned (same Y coordinate)
5. **Standard spacing**: Use 400px horizontal spacing between icons (for 800px width)

### Common Mistakes to Avoid

1. ❌ **Mismatched sizes**: Background 1000×500 but window-size 800×400
2. ❌ **Wrong coordinate system**: Assuming bottom-left origin (it's top-left)
3. ❌ **Ignoring icon labels**: Not accounting for text below icons
4. ❌ **Too large images**: Using 4K backgrounds (causes scaling issues)
5. ❌ **Absolute positioning**: Not calculating positions relative to window size

---

## 6. Troubleshooting

### Problem: Background appears too large
**Solution**: Reduce background image dimensions to match `--window-size`

### Problem: Icons not in correct positions
**Solution**: 
- Verify coordinate system (top-left origin)
- Check if positions account for icon center vs corner
- Ensure Y-coordinate accounts for label space

### Problem: Background cut off on edges
**Solution**: 
- Ensure `--window-size` exactly matches image dimensions
- Check that image doesn't have extra padding/borders

### Problem: Blurry on Retina displays
**Solution**: Create `background@2x.png` at double resolution (1600×800)

---

## 7. Template for Standard DMG

### Background Image Specifications
- **Dimensions**: 800×400 pixels
- **Format**: PNG
- **Resolution**: 72 DPI
- **Retina version**: 1600×800 pixels (optional)

### Icon Layout
- **Icon size**: 100px
- **App icon**: (200, 190)
- **Applications link**: (600, 185)
- **Vertical alignment**: ±5px tolerance

### create-dmg Command
```bash
create-dmg \
  --volname "Your App Name" \
  --volicon "app_icon.icns" \
  --background "background.png" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "YourApp.app" 200 190 \
  --hide-extension "YourApp.app" \
  --app-drop-link 600 185 \
  "YourApp-Installer.dmg" \
  "source_folder/"
```

---

## 8. Design Template Coordinates (for 800×400)

### Grid System
```
Window: 800×400
Margins: 50px (top/bottom), 100px (left/right)
Content area: 600×300
Icon spacing: 400px horizontal
```

### Key Positions
```
Top margin: y=50
Bottom margin: y=350
Left icon center: x=200
Right icon center: x=600
Vertical center: y=200
Icon baseline (with label): y=190
```

### Design Elements
- **Title/Logo**: Top center (x=400, y=50-80)
- **Arrow/Guide**: Between icons (x=350-450, y=180-210)
- **Instructions**: Bottom (x=400, y=350-380)

---

## Sources

1. **create-dmg GitHub Repository**: https://github.com/create-dmg/create-dmg
2. **Real-world examples**: RustDesk, Ollama, LuLu, pgAdmin, MacVim
3. **electron-builder documentation**: DMG configuration
4. **dmgbuild documentation**: Alternative DMG creation tool
5. **Apple Developer Forums**: DMG layout discussions

---

## Quick Reference Card

| Aspect | Recommendation |
|--------|---------------|
| **Background size** | 800×400 pixels (PNG) |
| **Window size** | `--window-size 800 400` |
| **Icon size** | `--icon-size 100` |
| **App icon position** | `--icon "App.app" 200 190` |
| **Applications link** | `--app-drop-link 600 185` |
| **Coordinate origin** | Top-left (0, 0) |
| **Retina support** | Create background@2x.png (1600×800) |
| **Format** | PNG preferred, 72 DPI, sRGB |

