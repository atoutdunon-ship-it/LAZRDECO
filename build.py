#!/usr/bin/env python3
"""LAZERDECO — génère le site à partir des sources de ce dossier.

Sorties (un seul point de sortie, dans ce même dossier) :
  index.html            site public            ← gabarit.html + formes.js + produits.json
  admin.html            espace de gestion      ← gabarit-admin.html + formes.js + produits.json
  supabase-donnees.sql  données de départ      ← produits.json
  .nojekyll

Usage : python3 build.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MARK = "/*DATA*/null"
FORMES = "/*FORMES*/"
TARIFS = "/*TARIFS*/"
DEST_TVA = {"Martinique": 0.085, "Guadeloupe": 0.085, "Guyane": 0}


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        sys.exit(f"ARRÊT : {path.name} invalide, ligne {e.lineno} colonne {e.colno} : {e.msg}")


def check(data: dict) -> list[str]:
    errs: list[str] = []
    cats = {c["id"] for c in data["categories"]}
    techs = set(data["techniques"])
    refs: set[str] = set()
    for p in data["produits"]:
        r = p.get("ref", "?")
        if r in refs:
            errs.append(f"{r} : référence en double")
        refs.add(r)
        if p["cat"] not in cats:
            errs.append(f"{r} : catégorie inconnue « {p['cat']} »")
        if not p["tech"] or not set(p["tech"]) <= techs:
            errs.append(f"{r} : technologie inconnue {p['tech']}")
        q, pr = p["q"], p["p"]
        if len(q) != len(pr) or not 2 <= len(q) <= 6:
            errs.append(f"{r} : paliers et prix de longueurs différentes (2 à 6 paliers)")
        elif q != sorted(set(q)) or q[0] < 1:
            errs.append(f"{r} : quantités non strictement croissantes")
        elif any(a < b for a, b in zip(pr, pr[1:])) or min(pr) <= 0:
            errs.append(f"{r} : prix non dégressifs ou nuls")
    return errs


def sql_txt(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def sql_arr(vals, typ: str) -> str:
    return f"array[{', '.join(sql_txt(v) for v in vals)}]::{typ}[]"


def seed(data: dict) -> str:
    c = data["config"]
    out = ["-- LAZERDECO — données de départ, générées par build.py depuis produits.json.",
           "-- Ré-exécutable : les lignes existantes sont mises à jour.", "begin;"]
    for i, (k, t) in enumerate(data["techniques"].items()):
        out.append(f"insert into public.techniques (id, nom, detail, delai_jours, ordre) values ({sql_txt(k)}, {sql_txt(t['nom'])}, {sql_txt(t['detail'])}, {int(t.get('delai', 3))}, {i})"
                   " on conflict (id) do update set nom = excluded.nom, detail = excluded.detail, delai_jours = excluded.delai_jours, ordre = excluded.ordre;")
    for r in data.get("roles", []):
        out.append(f"insert into public.roles (id, nom, description, permissions, ordre) values ({sql_txt(r['id'])}, {sql_txt(r['nom'])}, {sql_txt(r['description'])}, "
                   f"{sql_txt(json.dumps(r['permissions'], ensure_ascii=False))}::jsonb, {int(r.get('ordre', 50))}) on conflict (id) do nothing;")
    for i, k in enumerate(data["categories"]):
        out.append(f"insert into public.categories (id, nom, accroche, couleur, ordre) values ({sql_txt(k['id'])}, {sql_txt(k['nom'])}, {sql_txt(k['accroche'])}, {sql_txt(k['couleur'])}, {i})"
                   " on conflict (id) do update set nom = excluded.nom, accroche = excluded.accroche, couleur = excluded.couleur, ordre = excluded.ordre;")
    for i, p in enumerate(data["produits"]):
        cols = ("ref, nom, categorie, techniques, description, quantites, prix, badge, emplacement, a_partir, image, forme, teinte, ordre")
        vals = ", ".join([sql_txt(p["ref"]), sql_txt(p["nom"]), sql_txt(p["cat"]), sql_arr(p["tech"], "text"), sql_txt(p["desc"]),
                          sql_arr(p["q"], "int"), sql_arr(p["p"], "numeric"), sql_txt(p.get("badge")), sql_txt(p.get("emplacement")),
                          sql_txt(bool(p.get("aPartir"))), sql_txt(p.get("img")), sql_txt(p.get("forme")), sql_txt(p.get("teinte")), str(i)])
        upd = ", ".join(f"{k.strip()} = excluded.{k.strip()}" for k in cols.split(",")[1:])
        out.append(f"insert into public.produits ({cols}) values ({vals}) on conflict (ref) do update set {upd};")
    for k, v in data.get("textes", {}).items():
        out.append(f"insert into public.textes (cle, valeur) values ({sql_txt(k)}, {sql_txt(v)}) on conflict (cle) do nothing;")
    params = {
        "marque": c["marque"], "email": c["email"], "whatsapp": c["whatsapp"], "telephone": c["telephone"],
        "adresse": c["adresse"], "logo": c["logo"], "tva": c.get("tva", DEST_TVA), "express": c["express"],
        "delais": c.get("delais", {}), "email_equipe": c.get("email_equipe", []), "site_url": c.get("site_url", ""),
        "accueil": data.get("accueil", {}), "seo": data.get("seo", {}), "modeles_emails": data.get("modeles_emails", {}),
    }
    for k, v in params.items():
        out.append(f"insert into public.parametres (cle, valeur) values ({sql_txt(k)}, {sql_txt(json.dumps(v, ensure_ascii=False))}::jsonb) on conflict (cle) do nothing;")
    for i, pg in enumerate(data.get("pages", [])):
        out.append(f"insert into public.pages (slug, titre, contenu, type, ordre) values ({sql_txt(pg['slug'])}, {sql_txt(pg['titre'])}, {sql_txt(pg['contenu'])}, "
                   f"{sql_txt(pg.get('type', 'libre'))}, {int(pg.get('ordre', i))}) on conflict (slug) do nothing;")
    out.append("commit;")
    return "\n".join(out) + "\n"


def page(gabarit: str, data: dict, formes: str) -> str:
    tpl = (ROOT / gabarit).read_text(encoding="utf-8")
    for m in (MARK, FORMES, TARIFS):
        if tpl.count(m) != 1:
            sys.exit(f"ARRÊT : marqueur {m} absent ou multiple dans {gabarit}")
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    return tpl.replace(MARK, payload).replace(FORMES, formes).replace(TARIFS, (ROOT / "tarifs.js").read_text(encoding="utf-8"))


def main() -> None:
    data = load(ROOT / "produits.json")
    if errs := check(data):
        sys.exit("ARRÊT : données incohérentes\n - " + "\n - ".join(errs))
    formes = (ROOT / "formes.js").read_text(encoding="utf-8")
    (ROOT / "index.html").write_text(page("gabarit.html", data, formes), encoding="utf-8")
    if (ROOT / "gabarit-admin.html").exists():
        (ROOT / "admin.html").write_text(page("gabarit-admin.html", data, formes), encoding="utf-8")
    (ROOT / "supabase-donnees.sql").write_text(seed(data), encoding="utf-8")
    (ROOT / ".nojekyll").touch()
    sb = data["config"].get("supabase", {})
    mode = "connecté à Supabase" if sb.get("url") and sb.get("cle_publique") else "mode hors ligne (Supabase non configuré)"
    print(f"Site généré : {len(data['produits'])} produits, {len(data['categories'])} univers — {mode}.")


if __name__ == "__main__":
    main()
