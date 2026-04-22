"""Generate pixel art assets via Gemini web (connected to real Chrome)."""
import sys, os, time, glob, json
from playwright.sync_api import sync_playwright
from PIL import Image
from rembg import remove
import io

def get_ws_url():
    import requests, json
    r = requests.get('http://127.0.0.1:9333/json/version', timeout=5)
    return r.json()['webSocketDebuggerUrl']

WS_URL = None  # resolved at runtime
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "img", "scene")
os.makedirs(OUT_DIR, exist_ok=True)

STYLE = (
    "pixel art game sprite, blocky simple shapes, thick dark outlines, "
    "warm muted earthy colors, side view, single isolated object, "
    "white background, retro low resolution style like Madness Combat game, "
    "no anti-aliasing, clean pixel edges, no text"
)

OFFICE = [
    ("floor_tile", "seamless office gray carpet floor texture, top-down view"),
    ("wall_back", "flat beige office wall with dark baseboard, side view"),
    ("desk_wood", "wooden office desk with 2 drawers, side view from slightly above"),
    ("desk_metal", "modern metal office desk, clean lines, side view"),
    ("chair_office", "orange office swivel chair with wheels, side view"),
    ("chair_simple", "simple dark office chair, side view"),
    ("pc_monitor", "computer LCD monitor on stand, front-side view"),
    ("keyboard", "computer keyboard, top view, small"),
    ("coffee_mug", "white coffee mug with brown coffee, side view"),
    ("desk_lamp", "adjustable desk lamp, side view"),
    ("trash_can", "round metal office trash can, side view"),
    ("water_cooler", "tall water cooler dispenser, side view"),
    ("filing_cabinet", "metal filing cabinet 3 drawers, side view"),
    ("potted_plant", "small green potted office plant, side view"),
    ("wall_clock", "round wall clock with numbers, front view"),
    ("red_stapler", "red stapler, side view"),
    ("office_door", "closed office door with handle, side view"),
    ("bookshelf", "small bookshelf with colorful books, side view"),
]


def gen_one(page, name, desc):
    """Type prompt in Gemini, wait for image, download it."""
    prompt = f"Generate a single {desc}. Style: {STYLE}"
    print(f"  [{name}] prompting...", end=" ", flush=True)

    try:
        # Start new chat (click the new chat button)
        new_chat = page.query_selector('[aria-label*="New chat"], [aria-label*="Новый чат"], a[href="/app"]')
        if new_chat:
            new_chat.click()
            time.sleep(2)

        # Find input area
        input_area = page.wait_for_selector('.ql-editor, [contenteditable="true"], textarea', timeout=10000)
        input_area.click()
        time.sleep(0.3)

        # Type prompt
        input_area.type(prompt, delay=5)
        time.sleep(0.5)

        # Send (Enter)
        page.keyboard.press("Enter")
        print("sent, waiting...", end=" ", flush=True)

        # Wait for response (image takes 15-45s)
        time.sleep(40)

        # Scroll to bottom to see latest response
        page.keyboard.press("End")
        time.sleep(2)

        # Find generated images - look for img tags with substantial size
        # Take screenshot of the response area for debugging
        all_imgs = page.query_selector_all('img')
        best_img = None
        best_size = 0

        for img in all_imgs:
            try:
                box = img.bounding_box()
                if box and box['width'] > 100 and box['height'] > 100:
                    size = box['width'] * box['height']
                    if size > best_size:
                        best_size = size
                        best_img = img
            except:
                pass

        if best_img:
            filepath = os.path.join(OUT_DIR, f"{name}_raw.png")
            best_img.screenshot(path=filepath)
            print(f"captured ({best_size:.0f}px2)", end=" ", flush=True)

            # Process: remove bg + resize
            processed = process_asset(filepath, name)
            if processed:
                print(f"OK -> {processed}")
                return processed
            else:
                print("process failed")
                return filepath
        else:
            # Fallback: screenshot entire page
            fallback = os.path.join(OUT_DIR, f"{name}_page.png")
            page.screenshot(path=fallback)
            print(f"no image found, page screenshot saved")
            return None

    except Exception as e:
        print(f"ERROR: {e}")
        return None


def process_asset(raw_path, name):
    """Remove background and resize."""
    try:
        with open(raw_path, 'rb') as f:
            img_data = f.read()
        clean = remove(img_data)
        img = Image.open(io.BytesIO(clean)).convert("RGBA")

        # Auto-crop to content
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)

        # Save
        out = os.path.join(OUT_DIR, f"{name}.png")
        img.save(out)
        return out
    except Exception as e:
        print(f"  process error: {e}")
        return None


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python gemini_gen.py office      - generate all")
        print('  python gemini_gen.py "prompt" name - generate one')
        sys.exit(0)

    p = sync_playwright().start()
    ws = get_ws_url()
    print(f"WS: {ws[:60]}")
    browser = p.chromium.connect_over_cdp(ws)
    ctx = browser.contexts[0]
    page = ctx.pages[0]
    print(f"Connected to: {page.url[:50]}")

    if sys.argv[1] == "office":
        print(f"\nGenerating {len(OFFICE)} objects...\n")
        for name, desc in OFFICE:
            gen_one(page, name, desc)
            time.sleep(3)  # cooldown between requests
    else:
        prompt = sys.argv[1]
        name = sys.argv[2] if len(sys.argv) > 2 else "custom"
        gen_one(page, name, prompt)

    browser.close()
    p.stop()
    print("\nDone!")
