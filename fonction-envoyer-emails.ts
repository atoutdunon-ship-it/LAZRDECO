// LAZERDECO — fonction Supabase Edge « envoyer-emails »
// Envoie les e-mails en attente de la table « emails » via Resend (https://resend.com).
// Appel : bouton « Envoyer maintenant » de l'espace de gestion, ou webhook de base de données sur l'insertion dans « emails ».
// Secrets à définir (Edge Functions › Secrets) :
//   RESEND_API_KEY  clé API Resend
//   EXPEDITEUR      ex. « LAZR DECO <contact@votre-domaine.com> » (domaine vérifié dans Resend)
//   WEBHOOK_SECRET  chaîne aléatoire, à reprendre dans l'en-tête x-webhook-secret du webhook
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reponse = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, "Content-Type": "application/json" } });
const MAX_TENTATIVES = 5;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const secret = Deno.env.get("WEBHOOK_SECRET") ?? "";

    const depuisWebhook = secret !== "" && req.headers.get("x-webhook-secret") === secret;
    if (!depuisWebhook) {
      const appelant = createClient(url, anon, {
        global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
        auth: { persistSession: false },
      });
      const { data: autorise } = await appelant.rpc("peut", { module: "emails", action: "modifier" });
      if (!autorise) return reponse({ erreur: "Action non autorisée pour votre profil." }, 403);
    }

    const cle = Deno.env.get("RESEND_API_KEY");
    const expediteur = Deno.env.get("EXPEDITEUR");
    if (!cle || !expediteur) {
      return reponse({
        configure: false,
        message: "Service d'envoi non configuré : ajoutez RESEND_API_KEY et EXPEDITEUR dans les secrets de la fonction. Les e-mails restent en attente.",
      });
    }

    const admin = createClient(url, service, { auth: { persistSession: false } });
    const { data: lot, error } = await admin.from("emails").select("*").eq("statut", "en_attente")
      .lt("tentatives", MAX_TENTATIVES).order("id").limit(25);
    if (error) throw error;

    let envoyes = 0, erreurs = 0;
    for (const m of lot ?? []) {
      const r = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${cle}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: expediteur, to: [m.destinataire], subject: m.sujet, text: m.corps }),
      });
      if (r.ok) {
        envoyes++;
        await admin.from("emails").update({ statut: "envoye", envoye_le: new Date().toISOString(), erreur: null,
          tentatives: m.tentatives + 1 }).eq("id", m.id);
      } else {
        erreurs++;
        const detail = (await r.text()).slice(0, 300);
        await admin.from("emails").update({
          statut: m.tentatives + 1 >= MAX_TENTATIVES ? "erreur" : "en_attente",
          erreur: `HTTP ${r.status} : ${detail}`, tentatives: m.tentatives + 1,
        }).eq("id", m.id);
      }
    }
    const { count } = await admin.from("emails").select("id", { count: "exact", head: true }).eq("statut", "en_attente");
    return reponse({ configure: true, envoyes, erreurs, restants: count ?? 0 });
  } catch (e) {
    return reponse({ erreur: e instanceof Error ? e.message : String(e) }, 500);
  }
});
