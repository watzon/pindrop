#!/bin/bash

# Download Lucide and brand icons for Pindrop
# Creates proper .imageset folders with Contents.json

ASSETS_DIR="Pindrop/Assets.xcassets/Icons"

# Icon definitions: "icon-id:asset-name"
ICONS=(
    # Microphone/Recording
    "lucide:mic:icon-mic"
    "lucide:mic-off:icon-mic-off"
    "lucide:circle-dot:icon-record"
    "lucide:audio-waveform:icon-waveform"
    
    # Settings tabs
    "lucide:settings:icon-settings"
    "lucide:keyboard:icon-keyboard"
    "lucide:cpu:icon-cpu"
    "lucide:sparkles:icon-sparkles"
    
    # Output options
    "lucide:clipboard-copy:icon-clipboard"
    "lucide:text-cursor-input:icon-text-cursor"
    
    # General UI
    "lucide:app-window:icon-window"
    "lucide:rotate-ccw:icon-reset"
    "lucide:clock:icon-clock"
    "lucide:history:icon-history"
    "lucide:search:icon-search"
    
    # Export
    "lucide:share:icon-export"
    "lucide:file-text:icon-file-text"
    "lucide:braces:icon-json"
    "lucide:table:icon-table"
    "lucide:copy:icon-copy"
    
    # Status
    "lucide:check-circle:icon-check"
    "lucide:triangle-alert:icon-warning"
    "lucide:shield-check:icon-shield"
    "lucide:info:icon-info"
    "lucide:loader-circle:icon-loading"
    
    # Visibility
    "lucide:eye:icon-eye"
    "lucide:eye-off:icon-eye-off"
    
    # Navigation
    "lucide:chevron-left:icon-chevron-left"
    "lucide:chevron-right:icon-chevron-right"
    "lucide:arrow-right:icon-arrow-right"
    "lucide:download:icon-download"
    
    # Misc
    "lucide:hand:icon-hand"
    "lucide:construction:icon-construction"
    "lucide:x-circle:icon-close"
    "lucide:server:icon-server"
    "lucide:router:icon-router"
    "lucide:hard-drive:icon-hard-drive"
    "lucide:zap:icon-zap"
    "lucide:target:icon-target"
    
    # Brand icons
    "simple-icons:openai:icon-openai"
    "simple-icons:anthropic:icon-anthropic"
    "simple-icons:google:icon-google"
)

mkdir -p "$ASSETS_DIR"

for entry in "${ICONS[@]}"; do
    IFS=':' read -r prefix name asset_name <<< "$entry"
    icon_id="${prefix}:${name}"
    
    echo "Downloading $icon_id -> $asset_name..."
    
    # Create imageset folder
    imageset_dir="$ASSETS_DIR/${asset_name}.imageset"
    mkdir -p "$imageset_dir"
    
    # Download SVG
    npx better-icons get "$icon_id" --size 24 > "$imageset_dir/${asset_name}.svg" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Create Contents.json for SVG
        cat > "$imageset_dir/Contents.json" << EOF
{
  "images" : [
    {
      "filename" : "${asset_name}.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
EOF
        echo "  Created $asset_name.imageset"
    else
        echo "  FAILED to download $icon_id"
        rm -rf "$imageset_dir"
    fi
done

echo ""
echo "Done! Icons saved to $ASSETS_DIR"
