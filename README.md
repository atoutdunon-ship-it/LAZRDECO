# LAZERDECO — site, espace client et espace de gestion

- `index.html` : le site public. Il contient le catalogue de 44 produits et les prix dégressifs. Les clients y créent leur compte, envoient leurs demandes de devis et suivent leurs commandes.
- `admin.html` : l'espace de gestion complet de l'équipe (18 écrans), avec des **rôles personnalisables**.
- Les comptes, les données et les photos sont hébergés par **Supabase**. Le site lui-même reste sur **GitHub Pages**.

Tant que Supabase n'est pas configuré, rien n'est bloqué :
- le site fonctionne avec le catalogue intégré, et les devis partent par e-mail ou WhatsApp ;
- `admin.html` s'ouvre en **mode démonstration** : on choisit un profil (Administrateur, Créateur, Gestion, Atelier) pour tout essayer sans rien enregistrer.

## Les modules de l'espace de gestion

| Rubrique | Modules |
|---|---|
| Pilotage | Tableau de bord · Statistiques (CA par mois, univers, machine, produit) et exports CSV |
| Catalogue | Produits et tarifs dégressifs · Univers · Machines (délais) · Promotions · Médiathèque |
| Ventes | Devis et commandes (lignes, prix forcé, code promo, BAT) · Production par machine · Paiements · Clients et tarifs pro |
| Site | Page d'accueil (ordre des sections, bannière, sélection) · Pages légales et libres · Référencement · Textes |
| Administration | Utilisateurs (invitation, rôle, désactivation) · Rôles et droits · Paramètres et modèles d'e-mails · File d'e-mails · Journal |

## Rôles et droits

Chaque rôle est une grille **module × action** (voir, créer, modifier, supprimer), réglée dans **Rôles et droits**. Rôles fournis :

| Rôle | Droits de départ |
|---|---|
| **Administrateur** | Tout, sans exception (rôle système, non modifiable) |
| **Créateur** | Produits (voir, créer, modifier), médiathèque, consultation des univers, machines et promotions |
| **Gestion** | Devis, BAT et commandes, production, paiements, clients et tarifs pro, statistiques, file d'e-mails |
| **Atelier** | File de production par machine (démarrer, terminer), consultation des produits |
| Client | Rien dans l'espace de gestion. Sur le site : ses devis, ses BAT (valider ou demander une correction), ses paiements |

Les droits sont appliqués **par la base de données**, pas seulement par l'interface. Quelques garanties :
- seul un administrateur peut donner le rôle Administrateur ou accorder les droits « Utilisateurs » et « Rôles » ;
- personne ne peut modifier son propre rôle, ni désactiver son propre compte ;
- un client ne fixe jamais un prix : prix, promotions, tarif pro et code promo sont recalculés par le serveur ;
- l'atelier ne peut changer que l'avancement des lignes ;
- un compte désactivé perd immédiatement tous ses droits. Un compte qui a des devis ne se supprime pas : il se désactive, l'historique est conservé.

Chaque action est inscrite au journal : auteur, rôle, valeur avant et après.

## Mise en service de Supabase (une seule fois, 30 minutes environ)

1. Créer un compte sur [supabase.com](https://supabase.com), puis un projet (région Europe).
2. **SQL Editor** › New query : coller tout `supabase-schema.sql` › Run. Puis une nouvelle requête avec `supabase-donnees.sql` › Run.
3. **Project Settings › API** : copier le *Project URL* et la clé *anon public*. Dans `produits.json` :
   `"supabase": {"url": "https://xxxx.supabase.co", "cle_publique": "eyJ…"}`
   La clé *anon* est faite pour être publique. **Ne jamais mettre la clé `service_role` dans le site.**
4. **Authentication › URL Configuration** : *Site URL* = l'adresse du site (ex. `https://compte.github.io/lazerdeco/`), et ajouter `…/admin.html` dans *Redirect URLs*.
5. **Edge Functions** › Deploy a new function, deux fois :
   - `gestion-comptes` : coller `fonction-gestion-comptes.ts` (invitations et suppression de comptes) ;
   - `envoyer-emails` : coller `fonction-envoyer-emails.ts` (envoi des e-mails automatiques).
6. Lancer `Regenerer-le-site.command`, puis envoyer les fichiers sur GitHub.
7. **Premier administrateur** : s'inscrire depuis « Mon compte » sur le site, confirmer l'e-mail, puis dans SQL Editor :
   `update public.profils set role = 'admin' where email = 'votre@adresse.fr';`
8. Dans **admin.html › Paramètres** : renseigner l'adresse du site et les e-mails de l'équipe. Puis inviter l'équipe depuis **Utilisateurs**.

## E-mails automatiques (quand le nom de domaine existera)

Les e-mails (nouvelle demande, changement de statut, BAT, réponse au BAT, paiement) sont créés dès maintenant dans **admin.html › E-mails**, en attente. Pour les envoyer :
1. Créer un compte [resend.com](https://resend.com) et y vérifier le nom de domaine.
2. **Edge Functions › Secrets** : `RESEND_API_KEY` (clé Resend), `EXPEDITEUR` (ex. `LAZR DECO <contact@votre-domaine.com>`), `WEBHOOK_SECRET` (une longue chaîne aléatoire).
3. **Database › Webhooks** › Create : table `emails`, événement *Insert*, type *Supabase Edge Functions* › `envoyer-emails`, en-tête `x-webhook-secret` = la même chaîne. Chaque e-mail part alors aussitôt ; le bouton « Envoyer maintenant » relance ceux qui restent.

Les textes des e-mails se modifient dans **Paramètres › Modèles d'e-mails**.

## Pages légales

Les mentions légales, CGV et la politique de confidentialité sont des **modèles à compléter** (« [à compléter] ») dans **Pages, accueil et SEO › Pages**. Les faire valider par un professionnel avant la mise en ligne.

## Mettre en ligne sur GitHub Pages

1. Dans le Finder, afficher les fichiers cachés avec **Cmd + Maj + .** Sinon `.nojekyll` n'est pas sélectionné. Ne pas le renommer.
2. Sur GitHub, créer un nouveau dépôt, puis **Add file → Upload files** et glisser tout le contenu du dossier (Cmd + A).
3. **Settings → Pages → Source : Deploy from a branch → `main` / `(root)`**.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html`, `admin.html` | Pages générées : ne pas modifier à la main |
| `produits.json` | Catalogue de départ, textes, rôles, accueil, pages, modèles d'e-mails et configuration Supabase |
| `gabarit.html`, `gabarit-admin.html` | Mise en page et logique du site et de l'espace de gestion |
| `formes.js` | Illustrations vectorielles des produits |
| `build.py` | Régénère les pages et `supabase-donnees.sql`, et contrôle la cohérence des prix |
| `tarifs.js` | Moteur de prix commun au site et à l'espace de gestion (identique au calcul de la base) |
| `supabase-schema.sql` | Tables, rôles et droits, règles de sécurité, calcul des prix, promotions, BAT, e-mails, journal, stockage |
| `fonction-gestion-comptes.ts`, `fonction-envoyer-emails.ts` | Fonctions serveur Supabase (invitations, envoi d'e-mails) |
| `supabase-donnees.sql` | Données de départ (générées) |
| `incruster.py` | Pose du logo sur les photos vierges (voir plus bas) |
| `logo-lazerdeco.jpg` | Logo |

Une fois Supabase en service, le catalogue se gère dans `admin.html` : la base fait foi. `produits.json` ne sert plus qu'au premier remplissage et au mode hors ligne.

## Photos réalistes des produits

Deux façons de faire :
- **Depuis admin.html** (profil Créateur ou Administrateur) : ouvrir la fiche du produit et choisir la photo. Elle est stockée dans Supabase.
- **Par lot, avec le logo incrusté** : télécharger les photos vierges listées dans `../LAZERDECO-PHOTOS/A-LIRE-photos-a-telecharger.md`, puis lancer `python3 incruster.py --apercu`. Le logo est mis à l'échelle, jamais modifié. On ajuste l'emplacement dans `zones.json`.
