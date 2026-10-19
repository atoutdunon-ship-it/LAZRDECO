/* LAZERDECO — moteur de prix partagé par le site et l'espace de gestion.
   Il reproduit exactement le calcul de la base (fonctions calcul_prix et remise_code) :
   palier → promotion produit → marquage supplémentaire → express → remise pro, arrondi au centime. */
const TARIF = {
  r2: n => Math.round((Number(n) + Number.EPSILON) * 100) / 100,
  jour: () => new Date().toISOString().slice(0, 10),
  enCours(x, jour) {
    const j = jour || TARIF.jour();
    return x && x.actif !== false && (!x.debut || x.debut <= j) && (!x.fin || x.fin >= j);
  },
  palier(p, q) { let u = null; (p.q || []).forEach((t, i) => { if (q >= t) u = Number(p.p[i]); }); return u; },
  promoPct(p, promos, jour) {
    let m = 0;
    (promos || []).forEach(x => {
      if (TARIF.enCours(x, jour) && (!x.produit || x.produit === p.ref) && (!x.univers || x.univers === p.cat)) m = Math.max(m, Number(x.pct));
    });
    return m;
  },
  /* o : {promos, emplacement, express, tauxExpress, remisePro, jour} → {u, pct, base} ou null sous le minimum */
  unitaire(p, q, o) {
    o = o || {};
    const base = TARIF.palier(p, q);
    if (base == null) return null;
    const pct = TARIF.promoPct(p, o.promos, o.jour);
    let u = base;
    if (pct) u = u * (1 - pct / 100);
    if (o.emplacement && p.emplacement) u += Number(p.emplacement);
    if (o.express) u = u * (1 + (o.tauxExpress == null ? 0.2 : Number(o.tauxExpress)));
    if (o.remisePro) u = u * (1 - Number(o.remisePro) / 100);
    return {u: TARIF.r2(u), pct, base};
  },
  /* c : code promo ; lignes : [{ref, cat, total}] ; o : {utilisations, jour} */
  code(c, lignes, o) {
    o = o || {};
    const non = m => ({ok: false, remise: 0, message: m});
    if (!c) return non('Ce code promo n’existe pas.');
    if (!TARIF.enCours(c, o.jour)) return non('Ce code promo n’est pas valable actuellement.');
    if (c.max_utilisations != null && (o.utilisations || 0) >= Number(c.max_utilisations)) return non('Ce code promo a atteint son nombre maximal d’utilisations.');
    const elig = TARIF.r2((lignes || []).filter(l => (!c.produit || l.ref === c.produit) && (!c.univers || l.cat === c.univers)).reduce((s, l) => s + Number(l.total || 0), 0));
    if (!(elig > 0)) return non('Ce code ne s’applique à aucun produit de votre sélection.');
    if (Number(c.minimum_ht || 0) > elig) return non('Ce code s’applique dès ' + String(Number(c.minimum_ht).toFixed(2)).replace('.', ',') + ' € HT d’achat.');
    const remise = c.type === 'pct' ? TARIF.r2(elig * Number(c.valeur) / 100) : TARIF.r2(Math.min(Number(c.valeur), elig));
    return {ok: true, remise, message: (c.type === 'pct' ? '−' + String(Number(c.valeur)).replace('.', ',') + ' %' : 'Remise') + ' appliquée'};
  }
};

/* Rendu des pages rédigées dans l'espace de gestion : ## titre, ### sous-titre, - liste, > encadré,
   **gras**, [texte](https://lien). Tout le reste est affiché comme du texte (aucun HTML accepté). */
const MD = {
  rendre(src) {
    const e = s => String(s).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
    const inl = s => e(s).replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+|#\/[a-z0-9/-]*)\)/g, '<a href="$2">$1</a>');
    const out = []; let liste = null, para = [];
    const finPara = () => { if (para.length) { out.push('<p>' + para.map(inl).join('<br>') + '</p>'); para = []; } };
    const finListe = () => { if (liste) { out.push('<ul>' + liste.map(x => '<li>' + inl(x) + '</li>').join('') + '</ul>'); liste = null; } };
    String(src || '').split(/\r?\n/).forEach(l => {
      const t = l.trim(); let m;
      if (!t) { finPara(); finListe(); return; }
      if ((m = t.match(/^(#{2,3})\s+(.*)$/))) { finPara(); finListe(); out.push(`<h${m[1].length}>${inl(m[2])}</h${m[1].length}>`); return; }
      if ((m = t.match(/^>\s?(.*)$/))) { finPara(); finListe(); out.push('<p class="md-note">' + inl(m[1]) + '</p>'); return; }
      if ((m = t.match(/^[-*]\s+(.*)$/))) { finPara(); (liste = liste || []).push(m[1]); return; }
      finListe(); para.push(t);
    });
    finPara(); finListe();
    return out.join('');
  }
};
