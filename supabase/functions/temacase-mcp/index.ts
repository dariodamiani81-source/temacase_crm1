import { createMcpHandler, McpServer } from "npm:@modelcontextprotocol/server";
import { pipeline } from "npm:@supabase/middleware@1";
import {
  withOAuthProtectedResource,
  withSupabase,
} from "npm:@supabase/server@1";
import { z } from "npm:zod@4";
import {
  aggiornaEsitoVisita,
  cercaVisita,
  cercaVisite,
} from "./visite.ts";

const schemaCodiceVisita = z.string().regex(/^VIS-[0-9]{3,12}$/);

function risultatoTesto(dati: unknown, isError = false) {
  return {
    content: [{ type: "text" as const, text: JSON.stringify(dati) }],
    isError,
  };
}

async function eseguiAzione<T>(
  azione: string,
  operazione: () => Promise<T>,
  operazioneFallita: (risultato: T) => boolean = () => false,
) {
  const inizio = performance.now();
  console.info(`temacase_mcp: ${azione} avviata`);

  try {
    const risultato = await operazione();
    const fallita = operazioneFallita(risultato);

    console.info(
      `temacase_mcp: ${azione} terminata`,
      JSON.stringify({
        riuscita: !fallita,
        durata_ms: Math.round(performance.now() - inizio),
      }),
    );

    return risultatoTesto(risultato, fallita);
  } catch (errore) {
    const codice = (errore as { code?: unknown } | null)?.code;
    const codiceLog =
      typeof codice === "string" && /^[A-Z0-9_]{1,40}$/.test(codice)
        ? codice
        : "SENZA_CODICE";

    console.error(
      `temacase_mcp: ${azione} fallita`,
      JSON.stringify({
        codice: codiceLog,
        database_url_configurata: Boolean(
          Deno.env.get("TEMACASE_DATABASE_URL"),
        ),
      }),
    );

    return {
      isError: true,
      content: [{
        type: "text" as const,
        text: "Operazione non riuscita. Verifica i log del connettore Temacase.",
      }],
    };
  }
}

const mcpHandler = createMcpHandler(() => {
  const server = new McpServer({
    name: "temacase-crm-test",
    version: "0.4.0",
  });

  server.registerTool(
    "cerca_visita",
    {
      description:
        "Legge una visita per codice esatto, ad esempio VIS-001. " +
        "Restituisce cliente, immobile, data, stato ed esito attuale.",
      inputSchema: {
        codice_visita: schemaCodiceVisita,
      },
      annotations: {
        readOnlyHint: true,
        openWorldHint: false,
      },
    },
    async ({ codice_visita }) =>
      eseguiAzione("cerca_visita", () => cercaVisita(codice_visita)),
  );

  server.registerTool(
    "cerca_visite",
    {
      description:
        "Cerca visite per cliente, indirizzo e/o data. " +
        "Fornisci almeno un filtro. I filtri forniti si applicano insieme. " +
        "Nome e indirizzo accettano testo parziale. " +
        "La data usa il formato YYYY-MM-DD e il fuso Europe/Rome. " +
        "Restituisce fino a 10 visite, dalla più recente.",
      inputSchema: {
        cliente: z.string().trim().min(1).max(160).optional(),
        indirizzo: z.string().trim().min(1).max(240).optional(),
        data_visita: z.iso.date().optional(),
      },
      annotations: {
        readOnlyHint: true,
        openWorldHint: false,
      },
    },
    async (input) => {
      if (!input.cliente && !input.indirizzo && !input.data_visita) {
        return risultatoTesto({
          messaggio: "Indica almeno un cliente, un indirizzo o una data.",
        }, true);
      }

      return eseguiAzione("cerca_visite", () => cercaVisite(input));
    },
  );

  server.registerTool(
    "aggiorna_esito_visita",
    {
      description:
        "Aggiorna solo l'esito di una visita. Usa il codice e l'esito attuale " +
        "letti con cerca_visita o cerca_visite. " +
        "Se l'esito è cambiato, rileggi la visita prima di riprovare.",
      inputSchema: {
        codice_visita: schemaCodiceVisita,
        esito_precedente: z.string().nullable(),
        nuovo_esito: z.string().trim().min(1).max(2000),
      },
      annotations: {
        readOnlyHint: false,
        destructiveHint: true,
        openWorldHint: false,
      },
    },
    async (input) =>
      eseguiAzione(
        "aggiorna_esito_visita",
        () => aggiornaEsitoVisita(input),
        (risultato) => !risultato.aggiornato,
      ),
  );

  return server;
});

Deno.serve(
  pipeline(
    [withOAuthProtectedResource(), withSupabase({ auth: "user" })],
    async (request, { supabase }) => {
      const utenteConsentito = Deno.env.get("TEMACASE_ALLOWED_USER_ID");

      if (!utenteConsentito) {
        return new Response("Utente di test da configurare.", { status: 503 });
      }

      const token = request.headers.get("Authorization")
        ?.match(/^Bearer\s+(\S+)$/i)?.[1];

      if (!token) {
        return new Response("Autenticazione richiesta.", { status: 401 });
      }

      const { data, error } = await supabase.auth.getUser(token);

      if (error || data.user?.id !== utenteConsentito) {
        return new Response("Utente non autorizzato.", { status: 403 });
      }

      return mcpHandler.fetch(request);
    },
  ),
);