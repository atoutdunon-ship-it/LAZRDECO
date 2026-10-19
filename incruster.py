#!/usr/bin/env python3
"""LAZERDECO — incruste le logo sur les photos vierges des produits.

Source  : ../LAZERDECO-PHOTOS/vierge-<ref>.jpg|jpeg|png|webp (ex. vierge-t-01.jpg)
Réglages: ../LAZERDECO-PHOTOS/zones.json (centre x, y et largeur l en fraction de l'image)
Sortie  : p-<ref>.jpg dans ce dossier, champ "img" mis à jour dans produits.json, puis build.py.

Le logo n'est jamais modifié : il est seulement mis à l'échelle.
- logo-lazerdeco.png (fond transparent) s'il existe : posé normalement, sur tout support.
- sinon logo-lazerdeco.jpg (fond noir) : fusion « écran », le noir disparaît sur les
  supports foncés ; sur un support clair le logo ressort délavé, le produit est signalé.

Usage : python3 incruster.py [--ref T-01 ...] [--apercu]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageStat
except ImportError:
    sys.exit("ARRÊT : installez Pillow  →  python3 -m pip install Pillow")

ROOT = Path(__file__).resolve().parent
PHOTOS = ROOT.parent / "LAZERDECO-PHOTOS"
TAILLE = 1000
DEFAUT = {"x": 0.5, "y": 0.5, "l": 0.3, "opacite": 0.95}
EXT = (".jpg", ".jpeg", ".png", ".webp")


def carre(im: Image.Image) -> Image.Image:
    """Recadrage centré au carré puis redimensionnement à TAILLE (la photo, pas le logo)."""
    w, h = im.size
    c = min(w, h)
    im = im.crop(((w - c) // 2, (h - c) // 2, (w - c) // 2 + c, (h - c) // 2 + c))
    return im.resize((TAILLE, TAILLE), Image.LANCZOS)


def charger_logo() -> tuple[Image.Image, bool]:
    png = ROOT / "logo-lazerdeco.png"
    if png.exists():
        return Image.open(png).convert("RGBA"), True
    jpg = ROOT / "logo-lazerdeco.jpg"
    if not jpg.exists():
        sys.exit("ARRÊT : logo-lazerdeco.png ou logo-lazerdeco.jpg introuvable dans le dossier du site")
    return Image.open(jpg).convert("RGB"), False


def incruster(photo: Image.Image, logo: Image.Image, transparent: bool, z: dict) -> tuple[Image.Image, float]:
    lw = max(8, int(TAILLE * z["l"]))
    lh = max(8, int(lw * logo.height / logo.width))
    lg = logo.resize((lw, lh), Image.LANCZOS)
    x = int(TAILLE * z["x"] - lw / 2)
    y = int(TAILLE * z["y"] - lh / 2)
    box = (x, y, x + lw, y + lh)
    fond = photo.crop(box)
    luminance = ImageStat.Stat(fond.convert("L")).mean[0]
    if transparent:
        a = lg.getchannel("A").point(lambda v: int(v * z["opacite"]))
        photo.paste(lg.convert("RGB"), box, a)
    else:
        fusion = ImageChops.screen(fond, lg)
        photo.paste(Image.blend(fond, fusion, z["opacite"]), box)
    return photo, luminance


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", nargs="*", help="limiter à certaines références")
    ap.add_argument("--apercu", action="store_true", help="planche contact apercu-incrustation.jpg dans le dossier photos")
    args = ap.parse_args()

    if not PHOTOS.is_dir():
        sys.exit(f"ARRÊT : dossier {PHOTOS} introuvable")
    data = json.loads((ROOT / "produits.json").read_text(encoding="utf-8"))
    zf = PHOTOS / "zones.json"
    zones = json.loads(zf.read_text(encoding="utf-8")) if zf.exists() else {}
    logo, transparent = charger_logo()
    voulu = {r.upper() for r in args.ref} if args.ref else None

    faits, manquants, clairs, vignettes = [], [], [], []
    for p in data["produits"]:
        ref = p["ref"]
        if voulu and ref not in voulu:
            continue
        src = next((PHOTOS / f"vierge-{ref.lower()}{e}" for e in EXT if (PHOTOS / f"vierge-{ref.lower()}{e}").exists()), None)
        if not src:
            manquants.append(ref)
            continue
        z = {**DEFAUT, **zones.get(ref, {})}
        img, lum = incruster(carre(Image.open(src).convert("RGB")), logo, transparent, z)
        out = f"p-{ref.lower()}.jpg"
        img.save(ROOT / out, "JPEG", quality=86, optimize=True, progressive=True)
        p["img"] = out
        faits.append(ref)
        vignettes.append(img.resize((250, 250)))
        if not transparent and lum > 90:
            clairs.append(ref)

    (ROOT / "produits.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.apercu and vignettes:
        cols = 6
        planche = Image.new("RGB", (cols * 250, -(-len(vignettes) // cols) * 250), "white")
        for i, v in enumerate(vignettes):
            planche.paste(v, ((i % cols) * 250, (i // cols) * 250))
        planche.save(PHOTOS / "apercu-incrustation.jpg", quality=80)

    print(f"Incrustés : {len(faits)}  |  Photos manquantes : {len(manquants)}")
    if manquants:
        print("  manquantes : " + ", ".join(manquants))
    if clairs:
        print("  support clair, logo délavé (fournir logo-lazerdeco.png transparent) : " + ", ".join(clairs))
    subprocess.run([sys.executable, str(ROOT / "build.py")], check=True)


if __name__ == "__main__":
    main()
