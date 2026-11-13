import postgres from "npm:postgres@3.4.7";

type CercaVisiteInput = {
  cliente?: string;
  indirizzo?: string;
  data_visita?: string;
};

type AggiornaEsitoInput = {
  codice_visita: string;
  esito_precedente: string | null;
  nuovo_esito: string;
};

type Visita = {
  codice_visita: string;
  cliente: string;
  indirizzo: string;
  comune: string;
  data_ora_italiana: string;
  stato: string;
  esito: string | null;
};

type VisitaAggiornata = {
  codice_visita: string;
  esito: string;
};

let connessione: ReturnType<typeof postgres> | undefined;

function database() {
  if (connessione) return connessione;

  const url = Deno.env.get("TEMACASE_DATABASE_URL");
  if (!url) {
    throw new Error("Connessione al database da configurare.");
  }

  const indirizzo = new URL(url);
  const riferimento = "uuilnjjramxjvfoutmqu";
  const diretta = indirizzo.hostname === `db.${riferimento}.supabase.co`;
  const pooler = indirizzo.hostname.endsWith(".pooler.supabase.com");
  const utenteAtteso = diretta
    ? "temacase_mcp_login"
    : `temacase_mcp_login.${riferimento}`;

  console.info(
    "temacase_mcp: configurazione database",
    JSON.stringify({
      collegamento: diretta ? "diretto" : pooler ? "pooler" : "host inatteso",
      porta: indirizzo.port || "5432",
      utente_corretto: indirizzo.username === utenteAtteso,
      password_presente: indirizzo.password.length > 0,
    }),
  );

  connessione = postgres(url, {
    ssl: { rejectUnauthorized: true },
    max: 1,
    prepare: false,
    connect_timeout: 10,
    idle_timeout: 20,
  });

  return connessione;
}

function schedeVisite() {
  const sql = database();

  return sql`
    select
      v.codice as codice_visita,
      c.nome || ' ' || c.cognome as cliente,
      i.indirizzo,
      i.comune,
      to_char(
        v.data_visita at time zone 'Europe/Rome',
        'YYYY-MM-DD HH24:MI'
      ) as data_ora_italiana,
      v.stato,
      v.esito
    from temacase_test.visite v
    join temacase_test.clienti c on c.id = v.cliente_id
    join temacase_test.immobili i on i.id = v.immobile_id
  `;
}

export async function cercaVisita(codiceVisita: string) {
  const codice = codiceVisita.trim().toUpperCase();
  const sql = database();

  const [visita] = await sql<Visita[]>`
    ${schedeVisite()}
    where v.codice = ${codice}
  `;

  return visita
    ? { trovata: true as const, ...visita }
    : { trovata: false as const, codice_visita: codice };
}

export async function cercaVisite(input: CercaVisiteInput) {
  const cliente = input.cliente?.trim() || null;
  const indirizzo = input.indirizzo?.trim() || null;
  const data = input.data_visita || null;

  if (!cliente && !indirizzo && !data) {
    throw new Error("Indica almeno un filtro per cercare le visite.");
  }

  const sql = database();

  const visite = await sql<Visita[]>`
    ${schedeVisite()}
    where (
      ${cliente}::text is null
      or strpos(
        lower(c.nome || ' ' || c.cognome),
        lower(${cliente}::text)
      ) > 0
      or strpos(
        lower(c.cognome || ' ' || c.nome),
        lower(${cliente}::text)
      ) > 0
    )
    and (
      ${indirizzo}::text is null
      or strpos(lower(i.indirizzo), lower(${indirizzo}::text)) > 0
    )
    and (
      ${data}::date is null
      or (v.data_visita at time zone 'Europe/Rome')::date = ${data}::date
    )
    order by v.data_visita desc, v.codice asc
    limit 11
  `;

  return {
    visite: visite.slice(0, 10),
    altri_risultati: visite.length > 10,
  };
}

export async function aggiornaEsitoVisita(input: AggiornaEsitoInput) {
  const codice = input.codice_visita.trim().toUpperCase();
  const nuovoEsito = input.nuovo_esito.trim();

  if (!/^VIS-[0-9]{3,12}$/.test(codice)) {
    throw new Error("Indica un codice visita valido, ad esempio VIS-001.");
  }

  if (nuovoEsito.length === 0 || nuovoEsito.length > 2000) {
    throw new Error("L'esito deve contenere da 1 a 2000 caratteri.");
  }

  const sql = database();

  const [visita] = await sql<VisitaAggiornata[]>`
    update temacase_test.visite
    set esito = ${nuovoEsito}
    where codice = ${codice}
      and esito is not distinct from ${input.esito_precedente}
    returning codice as codice_visita, esito
  `;

  if (!visita) {
    return {
      aggiornato: false as const,
      messaggio: "Visita non trovata o esito cambiato. Rileggi la scheda.",
    };
  }

  return { aggiornato: true as const, ...visita };
}