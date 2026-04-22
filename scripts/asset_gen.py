"""
Office Jerk 2D — Asset Generator via Gemini
Generates individual pixel art objects for game scenes.
Each object is generated separately, analyzed, and saved.
"""

import os, sys, json, base64
from pathlib import Path
from google import genai
from google.genai import types
from PIL import Image
import io

API_KEY = os.environ.get("GEMINI_API_KEY", "AIzaSyC7Ri0isLBjavkbivgwQAO75QUhDlSn59o")
PROJECT_DIR = Path(__file__).parent.parent
ASSETS_DIR = PROJECT_DIR / "assets" / "img" / "scene"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

client = genai.Client(api_key=API_KEY)

# Base style prompt for consistency
STYLE = """pixel art, 2D side-view, blocky style similar to Madness Combat or Office Jerk game,
dark outlines, simple shapes, transparent background (PNG with alpha),
low resolution sprite suitable for a 2D game, clean edges, no anti-aliasing"""


def generate_object(name: str, description: str, size: str = "64x64") -> Path:
    """Generate a single game object sprite via Gemini."""

    prompt = f"""Generate a {size} pixel art sprite of: {description}

Style: {STYLE}

Important:
- Object should be on a transparent/checkerboard background
- Side view perspective
- Dark pixel art outlines
- Simple, clean, blocky shapes
- Suitable for a 2D office-themed fighting game
- The object should be clearly recognizable as: {name}"""

    print(f"  Generating: {name} ({size})...")

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash-image",
            contents=prompt,
            config=types.GenerateContentConfig(
                response_modalities=["TEXT", "IMAGE"],
            )
        )

        # Extract image from response
        for part in response.candidates[0].content.parts:
            if part.inline_data and part.inline_data.mime_type.startswith("image/"):
                img_data = part.inline_data.data
                img = Image.open(io.BytesIO(img_data))

                # Save
                out_path = ASSETS_DIR / f"{name}.png"
                img.save(out_path)
                print(f"  OK Saved: {out_path} ({img.size[0]}x{img.size[1]})")
                return out_path

        # No image in response — try text description
        print(f"  X No image generated for {name}, got text response")
        for part in response.candidates[0].content.parts:
            if part.text:
                print(f"    Response: {part.text[:200]}")
        return None

    except Exception as e:
        print(f"  X Error generating {name}: {e}")
        return None


def analyze_asset(path: Path, scene_context: str) -> dict:
    """Analyze if generated asset fits the scene."""
    if not path or not path.exists():
        return {"fits": False, "reason": "No image"}

    img = Image.open(path)
    img_bytes = io.BytesIO()
    img.save(img_bytes, format="PNG")
    img_b64 = base64.b64encode(img_bytes.getvalue()).decode()

    try:
        response = client.models.generate_content(
            model="gemini-2.0-flash-exp",
            contents=[
                types.Part.from_text(f"""Analyze this pixel art game sprite.
Does it fit an office scene for a 2D fighting game?
Scene context: {scene_context}

Rate 1-10 and explain briefly. Response as JSON:
{{"score": N, "fits": true/false, "issues": "...", "suggestion": "..."}}"""),
                types.Part.from_bytes(data=img_bytes.getvalue(), mime_type="image/png"),
            ],
        )

        text = response.candidates[0].content.parts[0].text
        # Try parse JSON
        text = text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0]
        return json.loads(text)
    except Exception as e:
        return {"score": 5, "fits": True, "issues": str(e)}


def generate_scene(scene_name: str, objects: list[dict]):
    """
    Generate all objects for a scene.

    objects: list of {"name": "chair", "desc": "office swivel chair", "size": "64x64"}
    """
    print(f"\n{'='*50}")
    print(f"  GENERATING SCENE: {scene_name}")
    print(f"  Objects: {len(objects)}")
    print(f"{'='*50}\n")

    results = []
    for obj in objects:
        name = obj["name"]
        desc = obj.get("desc", name)
        size = obj.get("size", "64x64")

        path = generate_object(name, desc, size)

        if path:
            analysis = analyze_asset(path, scene_name)
            score = analysis.get("score", 0)
            fits = analysis.get("fits", False)
            print(f"    Analysis: score={score}/10, fits={fits}")
            if analysis.get("issues"):
                print(f"    Issues: {analysis['issues']}")

            # Regenerate if score too low
            if score < 4:
                print(f"    Score too low, regenerating...")
                suggestion = analysis.get("suggestion", "")
                path = generate_object(name, f"{desc}. {suggestion}", size)

        results.append({"name": name, "path": str(path), "analysis": analysis if path else None})

    print(f"\n{'='*50}")
    print(f"  DONE: {sum(1 for r in results if r['path'])} / {len(objects)} generated")
    print(f"{'='*50}\n")
    return results


# ═══════════════════════════════════════
#  OFFICE SCENE PRESET
# ═══════════════════════════════════════
OFFICE_OBJECTS = [
    {"name": "desk", "desc": "wooden office desk, side view, brown", "size": "128x64"},
    {"name": "chair", "desc": "office swivel chair with wheels, side view", "size": "64x64"},
    {"name": "monitor", "desc": "computer monitor on desk, side view, dark screen", "size": "48x48"},
    {"name": "keyboard", "desc": "computer keyboard, side view, small", "size": "32x16"},
    {"name": "mug", "desc": "coffee mug, side view, white ceramic", "size": "24x24"},
    {"name": "phone", "desc": "desk telephone, office phone, side view", "size": "32x24"},
    {"name": "lamp", "desc": "desk lamp, side view, adjustable arm", "size": "48x48"},
    {"name": "trash_can", "desc": "office trash can, round metal, side view", "size": "32x40"},
    {"name": "water_cooler", "desc": "water cooler dispenser, office, side view, tall", "size": "48x96"},
    {"name": "filing_cabinet", "desc": "metal filing cabinet with drawers, side view", "size": "48x80"},
    {"name": "plant", "desc": "small potted office plant, side view", "size": "32x48"},
    {"name": "clock", "desc": "wall clock, round, side view", "size": "32x32"},
    {"name": "door", "desc": "office door, closed, with handle, side view", "size": "64x128"},
    {"name": "window", "desc": "office window with blinds, side view", "size": "80x96"},
    {"name": "bookshelf", "desc": "office bookshelf with books, side view", "size": "64x96"},
    {"name": "stapler", "desc": "red stapler, side view, small", "size": "24x16"},
    {"name": "pen_holder", "desc": "pen holder cup with pens, side view", "size": "24x32"},
    {"name": "paper_stack", "desc": "stack of papers, side view", "size": "24x16"},
]


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "office":
        generate_scene("Office Room", OFFICE_OBJECTS)
    elif len(sys.argv) > 2:
        # Custom: python asset_gen.py "name" "description" ["size"]
        name = sys.argv[1]
        desc = sys.argv[2]
        size = sys.argv[3] if len(sys.argv) > 3 else "64x64"
        path = generate_object(name, desc, size)
        if path:
            analysis = analyze_asset(path, "office fighting game")
            print(f"Analysis: {json.dumps(analysis, indent=2)}")
    else:
        print("Usage:")
        print("  python asset_gen.py office                    — generate full office scene")
        print('  python asset_gen.py "name" "description" [size] — generate single object')
        print()
        print("Example:")
        print('  python asset_gen.py "chair" "office swivel chair" "64x64"')
