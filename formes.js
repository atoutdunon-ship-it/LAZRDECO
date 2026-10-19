/* LAZERDECO — illustrations vectorielles des produits.
   Chaque forme : d = dessin SVG (viewBox 200×200), z = zones d'impression [x, y, l, h],
   f = teinte par défaut de l'objet ('cat' = couleur vive de l'univers), sombre = zone foncée. */
const NOIR = '#000000', BOIS = '#E2B07A', ACRY = '#EAF6FA', CUIR = '#7A4A26', PAPIER = '#FFFFFF', INOX = '#D9DEE5';
const S = 'stroke="#101826" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"';
const FORMES = {
  tshirt: {f: NOIR, z: [[70, 58, 60, 60]], d: c => `<path ${S} fill="${c}" d="M62 38 80 28q20 14 40 0l18 10 32 32-20 18-10-8v94H60V80l-10 8-20-18z"/>`},
  polo: {f: NOIR, z: [[106, 60, 32, 32]], d: c => `<path ${S} fill="${c}" d="M62 38 80 28q20 14 40 0l18 10 32 32-20 18-10-8v94H60V80l-10 8-20-18z"/><path ${S} fill="#fff" d="m82 30 18 22 18-22"/><path ${S} fill="none" d="M100 52v26"/>`},
  sweat: {f: NOIR, z: [[72, 66, 56, 56]], d: c => `<path ${S} fill="${c}" d="M64 40q36-26 72 0l36 30 4 92-20 2-8-70-2 80H54l-2-80-8 70-20-2 4-92z"/><path ${S} fill="none" d="M76 40q24 36 48 0"/><path ${S} fill="none" d="M70 140h60v32H70z"/>`},
  tote: {f: NOIR, z: [[60, 84, 80, 80]], d: c => `<path ${S} fill="none" stroke-width="6" d="M76 72q0-44 24-44t24 44"/><rect ${S} fill="${c}" x="48" y="70" width="104" height="112" rx="4"/>`},
  casquette: {f: NOIR, z: [[80, 70, 40, 40]], d: c => `<path ${S} fill="${c}" d="M44 122q0-64 56-64t56 64z"/><path ${S} fill="${c}" d="M44 122q60 14 132-4-14 24-76 24-42 0-56-20z"/><circle ${S} fill="${c}" cx="100" cy="58" r="5"/>`},
  tablier: {f: NOIR, z: [[70, 82, 60, 60]], d: c => `<path ${S} fill="none" d="M76 36q24-26 48 0"/><path ${S} fill="${c}" d="M76 36h48v34l26 14-6 92H56l-6-92 26-14z"/><path ${S} fill="none" d="M74 150h52v22H74z"/>`},
  bob: {f: NOIR, z: [[82, 66, 36, 36]], d: c => `<path ${S} fill="${c}" d="M64 106q0-48 36-48t36 48z"/><path ${S} fill="${c}" d="M30 110q70-20 140 0-4 22-70 22T30 110z"/>`},
  gourde: {f: NOIR, z: [[72, 90, 56, 56]], d: c => `<rect ${S} fill="#101826" x="82" y="24" width="36" height="32" rx="8"/><rect ${S} fill="${c}" x="68" y="52" width="64" height="128" rx="22"/><path stroke="#fff" stroke-width="5" stroke-linecap="round" d="M80 66v100" opacity=".7"/>`},
  mug: {f: NOIR, z: [[60, 78, 68, 68]], d: c => `<path ${S} fill="none" stroke-width="12" d="M134 80q34 0 34 30t-34 30"/><rect ${S} fill="${c}" x="50" y="58" width="88" height="110" rx="10"/>`},
  gobelet: {f: NOIR, z: [[72, 86, 56, 56]], d: c => `<path ${S} fill="${c}" d="M64 58h72l-10 120H74z"/><rect ${S} fill="#101826" x="58" y="40" width="84" height="20" rx="6"/>`},
  verre: {f: ACRY, z: [[78, 74, 44, 44]], d: c => `<path ${S} fill="${c}" d="M62 36h76l-12 136H74z"/><path ${S} fill="none" d="M66 62h68"/>`},
  bouteille: {f: '#BFE8D6', z: [[74, 112, 52, 46]], d: c => `<rect ${S} fill="#101826" x="86" y="18" width="28" height="18" rx="4"/><path ${S} fill="${c}" d="M88 36h24v24q24 14 24 40v78H64v-78q0-26 24-40z"/>`},
  stylo: {f: 'cat', z: [[66, 92, 68, 16]], d: c => `<g transform="rotate(35 100 100)"><rect ${S} fill="${c}" x="90" y="18" width="20" height="150" rx="10"/><path ${S} fill="#F4EEE7" d="m90 166 10 22 10-22z"/><rect ${S} fill="#101826" x="106" y="28" width="7" height="44" rx="3"/></g>`, rot: -55},
  stylobois: {f: BOIS, z: [[66, 92, 68, 16]], d: c => `<g transform="rotate(35 100 100)"><rect ${S} fill="${c}" x="90" y="18" width="20" height="150" rx="10"/><path ${S} fill="#F4EEE7" d="m90 166 10 22 10-22z"/></g>`, rot: -55},
  carnet: {f: NOIR, z: [[66, 66, 62, 62]], d: c => `<rect ${S} fill="${c}" x="52" y="30" width="96" height="140" rx="8"/><path ${S} fill="none" d="M66 30v140"/><rect ${S} fill="#101826" x="130" y="30" width="7" height="140"/>`},
  usb: {f: BOIS, z: [[78, 86, 44, 44]], d: c => `<rect ${S} fill="${INOX}" x="84" y="28" width="32" height="34" rx="3"/><rect ${S} fill="${c}" x="66" y="58" width="68" height="114" rx="14"/>`},
  badge: {f: ACRY, z: [[50, 80, 46, 46]], d: c => `<rect ${S} fill="${c}" x="34" y="62" width="132" height="80" rx="12"/><rect fill="#101826" x="104" y="88" width="50" height="9" rx="4"/><rect fill="#4F5B6B" x="104" y="106" width="36" height="8" rx="4"/>`},
  porteclesbois: {f: BOIS, z: [[72, 86, 56, 56]], d: c => `<circle ${S} fill="none" stroke-width="5" cx="100" cy="40" r="16"/><rect ${S} fill="${c}" x="58" y="58" width="84" height="112" rx="34"/><circle ${S} fill="#FFF9F3" cx="100" cy="72" r="6"/>`},
  porteclesrelief: {f: 'cat', z: [[64, 76, 72, 72]], d: c => `<circle ${S} fill="none" stroke-width="5" cx="100" cy="36" r="14"/><rect ${S} fill="${c}" x="54" y="52" width="92" height="118" rx="18"/><rect ${S} fill="#fff" x="62" y="72" width="76" height="80" rx="10"/>`},
  porteclesacry: {f: ACRY, z: [[66, 80, 68, 68]], d: c => `<circle ${S} fill="none" stroke-width="5" cx="100" cy="36" r="14"/><path ${S} fill="${c}" d="M100 52c40 0 56 30 56 62s-20 60-56 60-56-28-56-60 16-62 56-62z"/>`},
  magnet: {f: NOIR, z: [[60, 60, 80, 80]], d: c => `<circle ${S} fill="#4F5B6B" cx="106" cy="106" r="64"/><circle ${S} fill="${c}" cx="100" cy="100" r="64"/>`},
  decapsuleur: {f: BOIS, z: [[76, 100, 48, 48]], d: c => `<rect ${S} fill="${c}" x="66" y="24" width="68" height="152" rx="26"/><path ${S} fill="#FFF9F3" d="M84 50h32v16q0 12-16 12T84 66z"/><path ${S} fill="${INOX}" d="M86 48h28v8H86z"/>`},
  sousverre: {f: BOIS, z: [[66, 66, 68, 68]], d: c => `<circle ${S} fill="${c}" cx="100" cy="100" r="74"/><circle ${S} fill="none" stroke-dasharray="2 8" cx="100" cy="100" r="62"/>`},
  plaque: {f: ACRY, z: [[66, 68, 68, 68]], d: c => `<rect ${S} fill="${c}" x="22" y="50" width="156" height="102" rx="8"/>${[[36, 64], [164, 64], [36, 138], [164, 138]].map(([x, y]) => `<circle ${S} fill="${INOX}" cx="${x}" cy="${y}" r="6"/>`).join('')}`},
  presentoir: {f: 'cat', z: [[78, 52, 44, 44]], d: c => `<path ${S} fill="${c}" d="M70 36h60l12 124H58z"/><rect ${S} fill="#101826" x="46" y="158" width="108" height="18" rx="4"/><g fill="#101826"><rect x="82" y="108" width="14" height="14"/><rect x="104" y="108" width="14" height="14"/><rect x="82" y="130" width="14" height="14"/><rect x="108" y="134" width="6" height="6"/></g>`},
  chevalet: {f: ACRY, z: [[72, 50, 56, 56]], d: c => `<rect ${S} fill="${c}" x="56" y="30" width="88" height="128" rx="4"/><rect ${S} fill="#101826" x="44" y="156" width="112" height="18" rx="4"/><path stroke="#4F5B6B" stroke-width="5" stroke-linecap="round" d="M72 122h56M72 138h40"/>`},
  panneau: {f: BOIS, z: [[64, 62, 72, 72]], d: c => `<rect ${S} fill="${c}" x="20" y="46" width="160" height="112" rx="6"/><path stroke="#B8854F" stroke-width="2" fill="none" d="M24 70q40 8 80 0t72 4M24 140q50-6 90 2t62-4"/>`},
  enseigne: {f: '#F4EEE7', z: [[30, 30, 140, 140]], d: c => `<rect x="10" y="10" width="180" height="180" rx="16" fill="${c}"/><path stroke="#E6DED4" stroke-width="2" d="M10 60h180M10 110h180M10 160h180"/>`},
  trophee: {f: ACRY, z: [[72, 44, 56, 56]], d: c => `<path ${S} fill="${c}" d="M66 24h68v100q0 30-34 30t-34-30z"/><rect ${S} fill="${BOIS}" x="54" y="150" width="92" height="28" rx="4"/><path stroke="#4F5B6B" stroke-width="5" stroke-linecap="round" d="M80 118h40"/>`},
  planche: {f: BOIS, z: [[68, 88, 64, 64]], d: c => `<rect ${S} fill="${c}" x="44" y="30" width="112" height="150" rx="16"/><circle ${S} fill="#FFF9F3" cx="100" cy="52" r="9"/>`},
  cadre: {f: BOIS, z: [[74, 74, 52, 52]], d: c => `<rect ${S} fill="${c}" x="34" y="34" width="132" height="132" rx="4"/><rect ${S} fill="#FFF9F3" x="56" y="56" width="88" height="88"/>`},
  boite: {f: BOIS, z: [[74, 48, 52, 26]], d: c => `<rect ${S} fill="${c}" x="40" y="80" width="120" height="86" rx="4"/><rect ${S} fill="${c}" x="34" y="40" width="132" height="42" rx="4"/>`},
  cuir: {f: CUIR, z: [[72, 78, 56, 44]], sombre: true, d: c => `<rect ${S} fill="${c}" x="44" y="62" width="112" height="76" rx="16"/><rect fill="none" stroke="#E2B07A" stroke-width="2" stroke-dasharray="5 5" x="54" y="72" width="92" height="56" rx="10"/>`},
  figurine: {f: 'cat', z: [[84, 112, 32, 32]], d: c => `<ellipse ${S} fill="#101826" cx="100" cy="174" rx="54" ry="12"/><path ${S} fill="${c}" d="M66 172q0-82 34-82t34 82z"/><circle ${S} fill="${c}" cx="100" cy="60" r="28"/>`},
  feuille: {f: PAPIER, z: [[66, 52, 68, 68]], d: c => `<rect ${S} fill="#F4EEE7" x="62" y="34" width="96" height="136" rx="4" transform="rotate(8 110 100)"/><rect ${S} fill="${c}" x="50" y="30" width="96" height="136" rx="4"/><path stroke="#E6DED4" stroke-width="5" stroke-linecap="round" d="M66 138h64M66 152h44"/>`},
  stickers: {f: PAPIER, z: [[60, 44, 36, 36], [104, 44, 36, 36], [60, 92, 36, 36], [104, 92, 36, 36], [60, 140, 36, 22], [104, 140, 36, 22]], d: c => `<rect ${S} fill="${c}" x="48" y="30" width="104" height="142" rx="6"/>`},
  gateau: {f: '#FFE6EF', z: [[62, 56, 76, 40]], d: c => `<path ${S} fill="#FFB23E" d="M30 82v66q0 22 70 22t70-22V82"/><ellipse ${S} fill="${c}" cx="100" cy="80" rx="70" ry="24"/>`},
  toppers: {f: PAPIER, z: [[44, 50, 40, 40], [116, 50, 40, 40], [80, 114, 40, 40]], d: c => [[64, 70], [136, 70], [100, 134]].map(([x, y]) => `<circle ${S} fill="${c}" cx="${x}" cy="${y}" r="30"/>`).join('')},
  bandes: {f: '#FFF0D9', z: [[40, 112, 30, 30], [86, 112, 30, 30], [132, 112, 30, 30]], d: c => `<path ${S} fill="${c}" d="M24 76v80q0 20 76 20t76-20V76"/><ellipse ${S} fill="#FFE6EF" cx="100" cy="76" rx="76" ry="22"/><path ${S} fill="#fff" d="M24 106q76 20 152 0v42q-76 20-152 0z"/>`},
  etiquettes: {f: ACRY, z: [[70, 102, 60, 40]], d: c => `<rect ${S} fill="#101826" x="64" y="38" width="72" height="22" rx="6"/><rect ${S} fill="${c}" x="56" y="58" width="88" height="118" rx="16"/><rect ${S} fill="#fff" x="64" y="94" width="72" height="56" rx="6"/>`},
  rouleau: {f: PAPIER, z: [[52, 96, 40, 40], [100, 96, 40, 40]], d: c => `<path ${S} fill="${c}" d="M40 86h110v70H40z"/><ellipse ${S} fill="#F4EEE7" cx="150" cy="70" rx="18" ry="30"/><path ${S} fill="#F4EEE7" d="M40 40h110v60H40z"/><ellipse ${S} fill="#F4EEE7" cx="40" cy="70" rx="18" ry="30"/>`}
};
const FORME_REF = {
  'T-01': 'tshirt', 'T-02': 'tshirt', 'T-03': 'polo', 'T-04': 'sweat', 'T-05': 'tote', 'T-06': 'casquette', 'T-07': 'tablier', 'T-08': 'bob',
  'M-01': 'gourde', 'M-02': 'mug', 'M-03': 'gobelet', 'M-04': 'verre', 'M-05': 'bouteille',
  'B-01': 'stylo', 'B-02': 'stylobois', 'B-03': 'carnet', 'B-04': 'usb', 'B-05': 'badge',
  'G-01': 'porteclesbois', 'G-02': 'porteclesrelief', 'G-03': 'porteclesacry', 'G-04': 'magnet', 'G-05': 'decapsuleur', 'G-06': 'sousverre',
  'S-01': 'plaque', 'S-02': 'presentoir', 'S-03': 'chevalet', 'S-04': 'panneau', 'S-05': 'enseigne',
  'C-01': 'trophee', 'C-02': 'planche', 'C-03': 'cadre', 'C-04': 'boite', 'C-05': 'cuir', 'C-06': 'figurine',
  'P-01': 'feuille', 'P-02': 'feuille', 'P-03': 'gateau', 'P-04': 'toppers', 'P-05': 'bandes',
  'K-01': 'stickers', 'K-02': 'etiquettes', 'K-03': 'rouleau', 'K-04': 'feuille'
};
const VIVE = {mag: '#FF7AA2', cya: '#3FD0DC', ora: '#FFB23E', blu: '#6BB8EC'};
let LOGO_OK = false, DETOURE_OK = false;
const LOGO_DETOURE = 'logo-lazerdeco-detoure.png';
const VIVES = Object.values(VIVE);
/* Logo détouré (autorisé) sur supports clairs ou sombres ; logo d'origine sur fond noir pour les supports de couleur vive. */
function marque(x, y, w, h, sombre, fond) {
  const src = DETOURE_OK && !VIVES.includes(fond) ? LOGO_DETOURE : (LOGO_OK ? CFG.logo : null);
  if (src) return `<image href="${esc(src)}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid meet"/>`;
  const fs = Math.max(5, Math.min(h * 0.32, w / 5.6));
  const col = sombre ? '#FFF9F3' : '#A3123F';
  return `<text x="${x + w / 2}" y="${y + h / 2}" text-anchor="middle" dominant-baseline="middle" font-family="Fraunces, Georgia, serif" font-weight="900" font-size="${fs.toFixed(1)}" fill="${col}">LAZR<tspan x="${x + w / 2}" dy="${(fs * 1.05).toFixed(1)}">DECO</tspan></text>`;
}
function illustration(p) {
  const k = p.forme || FORME_REF[p.ref] || 'feuille';
  const F = FORMES[k] || FORMES.feuille;
  const fill = p.teinte || (F.f === 'cat' ? VIVE[catById[p.cat].couleur] : F.f);
  const zones = F.z.map(([x, y, w, h]) => marque(x, y, w, h, F.sombre, fill)).join('');
  const zg = F.rot ? `<g transform="rotate(${F.rot} 100 100)">${zones}</g>` : zones;
  return `<svg class="ill" viewBox="0 0 200 200" role="img" aria-label="${esc(p.nom)} marqué du logo ${esc(CFG.marque)}">${F.d(fill)}${zg}</svg>`;
}
function chargerLogo(apres) {
  const im = new Image();
  im.onload = () => { LOGO_OK = true; apres(); };
  im.src = CFG.logo;
  const d = new Image();
  d.onload = () => { DETOURE_OK = true; apres(); };
  d.src = LOGO_DETOURE;
}
