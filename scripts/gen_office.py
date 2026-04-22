"""Generate office scene assets via HuggingFace FLUX — each object separately."""
import requests, os, time, sys
from PIL import Image
from rembg import remove
import io

HF_TOKEN = "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"
API_URL = "https://router.huggingface.co/hf-inference/models/black-forest-labs/FLUX.1-schnell"
HEADERS = {"Authorization": f"Bearer {HF_TOKEN}"}
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "img", "scene")
os.makedirs(OUT_DIR, exist_ok=True)

# Style reference: blocky pixel art, thick dark outlines, warm muted colors
# View: 3/4 side view from slightly above (like Office Jerk / Madness Combat)
# Player is ~230px tall, objects must be proportional

STYLE = (
    "pixel art, 2D game sprite, thick dark outlines, blocky simple shapes, "
    "warm muted colors, side view slightly from above, single isolated object, "
    "white background, no shadows, clean edges, low resolution retro style, "
    "similar to Madness Combat or Office Jerk game art style"
)

# Objects to generate: name, description, target size (w, h)
OBJECTS = [
    ("floor", "office floor tiles, gray carpet texture, top-down view, seamless tileable pattern", 512, 128),
    ("wall_back", "office wall, beige flat wall with baseboard, side view, simple", 512, 256),
    ("wall_left", "office wall perspective from right side, beige, with corner", 128, 256),
    ("desk_1", "wooden office desk with drawers, side view from above", 200, 120),
    ("desk_2", "metal office desk, modern, side view from above", 200, 120),
    ("chair_1", "office swivel chair with wheels, side view", 80, 100),
    ("chair_2", "office chair, different style, side view", 80, 100),
    ("monitor", "computer LCD monitor on stand, front-side view", 64, 60),
    ("keyboard", "computer keyboard, top-side view, small", 48, 20),
    ("mug", "coffee mug, ceramic, side view", 24, 28),
    ("phone", "office desk telephone, side view", 40, 28),
    ("lamp", "desk lamp with adjustable arm, side view", 48, 64),
    ("trash_can", "round metal office trash can, side view", 36, 44),
    ("water_cooler", "water cooler dispenser, tall, side view", 48, 100),
    ("filing_cabinet", "metal filing cabinet 3 drawers, side view", 48, 96),
    ("plant", "small potted office plant, side view", 36, 52),
    ("clock", "round wall clock, front view", 32, 32),
    ("stapler", "red stapler, side view, small", 28, 16),
    ("paper_stack", "stack of papers on desk, side view", 32, 16),
    ("door", "office door closed with handle, side view", 80, 160),
    ("bookshelf", "small office bookshelf with books, side view", 64, 100),
    ("window", "office window with blinds half open, side view", 96, 120),
]


def generate(name, desc, w, h):
    prompt = f"{desc}, {STYLE}"
    print(f"  [{name}] generating {w}x{h}...", end=" ", flush=True)

    try:
        r = requests.post(API_URL, headers=HEADERS, json={"inputs": prompt}, timeout=90)
        if r.status_code == 503:
            print("model loading, waiting 20s...")
            time.sleep(20)
            r = requests.post(API_URL, headers=HEADERS, json={"inputs": prompt}, timeout=90)

        if r.status_code != 200 or "image" not in r.headers.get("content-type", ""):
            print(f"FAIL ({r.status_code})")
            return None

        # Load image
        img = Image.open(io.BytesIO(r.content)).convert("RGBA")

        # Remove background
        img_bytes = io.BytesIO()
        img.save(img_bytes, format="PNG")
        img_clean = remove(img_bytes.getvalue())
        img = Image.open(io.BytesIO(img_clean)).convert("RGBA")

        # Resize to target
        img = img.resize((w, h), Image.NEAREST)

        # Save
        out = os.path.join(OUT_DIR, f"{name}.png")
        img.save(out)
        print(f"OK -> {out}")
        return out

    except Exception as e:
        print(f"ERROR: {e}")
        return None


def analyze(path, name):
    """Quick check: is the image mostly transparent (bad) or has content (good)."""
    if not path:
        return False
    img = Image.open(path).convert("RGBA")
    pixels = list(img.getdata())
    opaque = sum(1 for r, g, b, a in pixels if a > 128)
    ratio = opaque / len(pixels)
    if ratio < 0.05:
        print(f"    WARNING: {name} is mostly transparent ({ratio:.0%} opaque) — may need regen")
        return False
    if ratio > 0.95:
        print(f"    WARNING: {name} has no transparency ({ratio:.0%} opaque) — bg removal failed")
        return False
    return True


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Generate single: python gen_office.py desk_1
        target = sys.argv[1]
        for name, desc, w, h in OBJECTS:
            if name == target:
                path = generate(name, desc, w, h)
                analyze(path, name)
                break
        else:
            print(f"Unknown object: {target}")
            print("Available:", ", ".join(o[0] for o in OBJECTS))
    else:
        # Generate ALL
        print(f"Generating {len(OBJECTS)} office objects...\n")
        results = []
        for name, desc, w, h in OBJECTS:
            path = generate(name, desc, w, h)
            ok = analyze(path, name)
            results.append((name, path, ok))
            time.sleep(1)  # rate limit

        print(f"\n{'='*40}")
        ok_count = sum(1 for _, _, ok in results if ok)
        print(f"Done: {ok_count}/{len(results)} good")
        for name, path, ok in results:
            status = "OK" if ok else "REDO"
            print(f"  [{status}] {name}")
