import os
from PIL import Image

# Paths
source_image = "/Users/grapeot/.gemini/antigravity/brain/311ed3f3-cc34-4ddd-9b1f-7473e9c0fe2e/opencode_logo_python_refined_1771186510585.png"
target_dir = "/Users/grapeot/Library/Mobile Documents/com~apple~CloudDocs/co/knowledge_working/adhoc_jobs/opencode_ios_client/OpenCodeClient/OpenCodeClient/Assets.xcassets/AppIcon.appiconset"

# Icon name for the 1024x1024 universal icon (which Xcode 15+ uses primarily)
target_filename = "AppIcon.png"
target_path = os.path.join(target_dir, target_filename)

def resize_icon():
    with Image.open(source_image) as img:
        # Resize to 1024x1024 for the App Store icon
        icon_1024 = img.resize((1024, 1024), Image.Resampling.LANCZOS)
        icon_1024.save(target_path, "PNG")
        print(f"Saved {target_path}")

if __name__ == "__main__":
    resize_icon()
