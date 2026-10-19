// LAZERDECO — fonction Supabase Edge « gestion-comptes »
// Invitation, renvoi d'invitation et suppression de comptes de l'équipe.
// Les droits de l'appelant sont vérifiés par la base (fonction peut()).
// Déploiement : Supabase › Edge Functions › Deploy a new function › « gestion-comptes », coller ce fichier.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reponse = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, "Content-Type": "application/json" } });
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reponse({ erreur: "Méthode non autorisée." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const jeton = req.headers.get("Authorization") ?? "";
    const appelant = createClient(url, anon, { global: { headers: { Authorization: jeton } }, auth: { persistSession: false } });
    const { data: moi } = await appelant.auth.getUser();
    if (!moi?.user) return reponse({ erreur: "Session expirée : reconnectez-vous." }, 401);

    const corps = await req.json().catch(() => ({}));
    const action = String(corps.action ?? "");
    const droits: Record<string, [string, string]> = {
      inviter: ["utilisateurs", "creer"],
      renvoyer: ["utilisateurs", "creer"],
      supprimer: ["utilisateurs", "supprimer"],
    };
    if (!droits[action]) return reponse({ erreur: "Action inconnue." }, 400);
    const { data: autorise } = await appelant.rpc("peut", { module: droits[action][0], action: droits[action][1] });
    if (!autorise) return reponse({ erreur: "Action non autorisée pour votre profil." }, 403);
    const { data: estAdmin } = await appelant.rpc("est_admin");

    const admin = createClient(url, service, { auth: { persistSession: false } });
    const site = String((await admin.from("parametres").select("valeur").eq("cle", "site_url").maybeSingle()).data?.valeur ?? "");
    const retour = site ? site.replace(/\/?$/, "/") + "admin.html" : undefined;
    const tracer = (cle: string, quoi: string, apres: Record<string, unknown>) =>
      admin.from("journal").insert({ qui: moi.user.id, qui_email: moi.user.email, table_nom: "profils", action: quoi, cle, apres });

    if (action === "inviter") {
      const email = String(corps.email ?? "").trim().toLowerCase();
      const nom = String(corps.nom ?? "").trim().slice(0, 80);
      const role = String(corps.role ?? "");
      if (!EMAIL.test(email)) return reponse({ erreur: "Adresse e-mail invalide." }, 400);
      const { data: r } = await admin.from("roles").select("id, equipe").eq("id", role).maybeSingle();
      if (!r || !r.equipe) return reponse({ erreur: "Choisissez un rôle d'équipe." }, 400);
      if (role === "admin" && !estAdmin) return reponse({ erreur: "Seul un administrateur peut inviter un administrateur." }, 403);
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { nom }, redirectTo: retour });
      if (error) {
        if (/already|registered|exists/i.test(error.message)) {
          return reponse({ erreur: "Un compte existe déjà avec cet e-mail : attribuez-lui le rôle depuis la liste des utilisateurs." }, 409);
        }
        throw error;
      }
      const { error: e2 } = await admin.from("profils").update({ role, nom, invite_le: new Date().toISOString() }).eq("id", data.user.id);
      if (e2) throw e2;
      await tracer(email, "invitation", { role, nom });
      return reponse({ ok: true, id: data.user.id });
    }

    const id = String(corps.id ?? "");
    const { data: cible } = await admin.from("profils").select("id, email, role").eq("id", id).maybeSingle();
    if (!cible) return reponse({ erreur: "Compte introuvable." }, 404);

    if (action === "renvoyer") {
      const { data: u } = await admin.auth.admin.getUserById(id);
      if (u?.user?.email_confirmed_at) {
        const { error } = await admin.auth.resetPasswordForEmail(cible.email, { redirectTo: retour });
        if (error) throw error;
      } else {
        const { error } = await admin.auth.admin.inviteUserByEmail(cible.email, { redirectTo: retour });
        if (error) throw error;
      }
      await admin.from("profils").update({ invite_le: new Date().toISOString() }).eq("id", id);
      await tracer(cible.email, "renvoi_invitation", {});
      return reponse({ ok: true });
    }

    // Suppression : uniquement un compte sans aucun devis ; sinon on le désactive (historique conservé).
    if (id === moi.user.id) return reponse({ erreur: "Vous ne pouvez pas supprimer votre propre compte." }, 400);
    if (cible.role === "admin" && !estAdmin) return reponse({ erreur: "Seul un administrateur peut supprimer un administrateur." }, 403);
    const { count } = await admin.from("devis").select("id", { count: "exact", head: true }).eq("client", id);
    if ((count ?? 0) > 0) {
      return reponse({ erreur: "Ce compte a des devis ou commandes : désactivez-le pour conserver l'historique." }, 409);
    }
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) throw error;
    await tracer(cible.email, "suppression", { role: cible.role });
    return reponse({ ok: true });
  } catch (e) {
    return reponse({ erreur: e instanceof Error ? e.message : String(e) }, 500);
  }
});
