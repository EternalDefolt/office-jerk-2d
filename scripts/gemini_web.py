"""
Gemini Web Image Generator — automates gemini.google.com via Playwright.
First run: opens browser for you to log in manually. Saves session.
Next runs: uses saved session, generates images automatically.

Usage:
  python gemini_web.py login              — open browser, log in manually
  python gemini_web.py "prompt here"      — generate single image
  python gemini_web.py office             — generate all office assets
"""

import sys, os, time, glob
from pathlib import Path
from playwright.sync_api import sync_playwright

SESSION_DIR = os.path.join(os.path.dirname(__file__), "..", ".gemini_session")
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "img", "scene")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(SESSION_DIR, exist_ok=True)

STYLE = (
    "pixel art game sprite, blocky simple shapes, thick dark outlines, "
    "warm muted colors, side view, single isolated object on pure white background, "
    "retro low resolution style like Madness Combat or Office Jerk game, "
    "no anti-aliasing, clean pixel edges"
)

OFFICE_OBJECTS = [
    ("floor_tile", "office gray carpet floor tile, top-down view, seamless texture pattern"),
    ("wall_back", "office beige wall with baseboard, flat side view, simple"),
    ("desk", "wooden office desk with drawers, side view from slightly above"),
    ("desk_metal", "modern metal office desk, clean, side view"),
    ("chair_office", "orange office swivel chair with wheels, side view"),
    ("chair_simple", "simple office chair, dark, side view"),
    ("monitor", "computer LCD monitor on stand, slight angle view"),
    ("keyboard", "computer keyboard, top-side view"),
    ("coffee_mug", "white coffee mug, side view"),
    ("desk_phone", "office desk telephone, side view"),
    ("desk_lamp", "desk lamp adjustable arm, side view"),
    ("trash_can", "round metal office trash can, side view"),
    ("water_cooler", "water cooler dispenser, tall, side view"),
    ("filing_cabinet", "metal filing cabinet with 3 drawers, side view"),
    ("potted_plant", "small green potted office plant, side view"),
    ("wall_clock", "round office wall clock, front view"),
    ("red_stapler", "red stapler, side view"),
    ("paper_stack", "stack of white papers, side view"),
    ("office_door", "office door with handle, closed, side view"),
    ("bookshelf", "small office bookshelf with books, side view"),
]


def login():
    """Open browser for manual Google login. Saves session."""
    with sync_playwright() as p:
        browser = p.chromium.launch_persistent_context(
            SESSION_DIR,
            headless=False,
            viewport={"width": 1280, "height": 900},
        )
        page = browser.new_page()
        page.goto("https://gemini.google.com/")
        print("Log in to Google in the browser window.")
        print("After logging in, press Enter here to save session...")
        input()
        browser.close()
        print("Session saved!")


def generate_image(prompt_text, filename):
    """Generate image via Gemini web interface."""
    full_prompt = f"{prompt_text}, {STYLE}"
    filepath = os.path.join(OUT_DIR, f"{filename}.png")

    print(f"  [{filename}] generating...", end=" ", flush=True)

    with sync_playwright() as p:
        browser = p.chromium.launch_persistent_context(
            SESSION_DIR,
            headless=False,
            viewport={"width": 1280, "height": 900},
        )
        page = browser.new_page()

        try:
            page.goto("https://gemini.google.com/", wait_until="networkidle", timeout=30000)
            time.sleep(2)

            # Find input field and type prompt
            # Gemini uses a rich text editor
            input_sel = 'div[contenteditable="true"], textarea, .ql-editor, [aria-label*="prompt"], [aria-label*="Enter"]'
            page.wait_for_selector(input_sel, timeout=15000)
            page.click(input_sel)
            page.keyboard.type(full_prompt, delay=10)
            time.sleep(0.5)

            # Submit (Enter)
            page.keyboard.press("Enter")

            # Wait for response with image
            print("waiting...", end=" ", flush=True)
            time.sleep(15)  # Gemini takes time to generate images

            # Look for generated images
            # Try to find and download the image
            images = page.query_selector_all('img[src*="blob:"], img[src*="data:image"], img.generated-image, img[alt*="Generated"]')

            if not images:
                # Scroll down and wait more
                page.mouse.wheel(0, 500)
                time.sleep(5)
                images = page.query_selector_all('img')
                # Filter to large images (likely generated, not UI elements)
                images = [img for img in images if (img.get_attribute("width") or "0").isdigit() and int(img.get_attribute("width") or "0") > 100]

            if images:
                # Download the last large image (most likely the generated one)
                for img in reversed(images):
                    src = img.get_attribute("src") or ""
                    if src.startswith("http") or src.startswith("blob:") or src.startswith("data:"):
                        # Screenshot the image element
                        img.screenshot(path=filepath)
                        print(f"OK -> {filepath}")
                        browser.close()
                        return filepath

            # Fallback: screenshot the response area
            print("no image found, taking screenshot...", end=" ", flush=True)
            page.screenshot(path=filepath.replace(".png", "_full.png"))
            print(f"screenshot saved")

        except Exception as e:
            print(f"ERROR: {e}")
        finally:
            browser.close()

    return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python gemini_web.py login         - log in to Google")
        print("  python gemini_web.py \"prompt\"       - generate single image")
        print("  python gemini_web.py office         - generate all office assets")
        sys.exit(0)

    cmd = sys.argv[1]

    if cmd == "login":
        login()
    elif cmd == "office":
        print(f"Generating {len(OFFICE_OBJECTS)} office objects via Gemini Web...\n")
        for name, desc in OFFICE_OBJECTS:
            generate_image(desc, name)
            time.sleep(2)
    else:
        # Single prompt
        name = sys.argv[2] if len(sys.argv) > 2 else "custom"
        generate_image(cmd, name)
