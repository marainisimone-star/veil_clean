# Veil Vetrina Blueprint v1.0

Data: 2026-02-09

Questa proposta integra il modello “Vetrina” **dentro** Veil (non come feature separata).
La vetrina è pubblica, con accesso multilivello, regole di ingaggio e moderazione equa.

## 1) Principi
- La vetrina è **pubblica**: tutti possono vedere.
- L’accesso attivo è **controllato** (partecipazione ammessa).
- Le regole **definiscono** la vetrina.
- Moderazione **non punitiva**, orientata al dialogo costruttivo.
- Niente “like” tradizionali: segnali di **qualità**, non popolarità.
- La vetrina **non è proprietaria**.
- Ranking **trasparente**: numeri + spiegazione + badge visibili.

## 2) Accesso (libero, senza approvazione manuale)
- Tutti possono **entrare e partecipare** subito.
- Nessun “request access”.
- Il creator **non** approva utenti: il controllo è solo comportamentale.

### Stati minimi (automazione AI)
- **active**: partecipazione normale.
- **warned**: warning attivo.
- **restricted**: limitazione temporanea.
- **excluded**: esclusione dalla vetrina.

## 3) Regole di ingaggio
### Regole Core (non modificabili)
- No insulti / odio / diffamazione.
- No discriminazioni.
- Linguaggio civile.

### Regole Opzionali (menu standard)
- Cite sources (5W baseline)
- Stay on topic
- Respect expertise level
- No spam or repetitive posts

### Linee guida (non vincolanti)
- Requisiti di studio (es. leggere un contenuto).
- Materiali consigliati (free/premium).
- Suggerimenti di AI per riassunti.
- Quiz come strumento di diffusione (non obbligatorio).

## 4) Moderazione AI (costruttiva)
- **Filtro immediato** per contenuti offensivi.
- **Grace period** per borderline: avviso + possibilità di modificare.
- Avvisi progressivi, poi sospensione temporanea.
- L’AI applica regole in modo **equo** (non il creator).

## 5) Ranking informativo “5W” (visibile a tutti)
Punteggio basato su:
- Who, What, Where, When, Why

Caratteristiche:
- È **interno** e calcolato da AI, non da utenti.
- Non giudica il sentiment.
- Premia chiarezza e informazioni verificabili.

**Peso prevalenza (v1)**
- Mass (visits) = 70%
- Quality = 20%
- Conversion = 10%

## 6) Vetrine figlie
### Creazione
- L’AI **suggerisce** quando un thread è off-topic ma interessante.
- **Chiunque** può creare una vetrina figlia (non solo il creator).
- La vetrina figlia non è proprietaria: possono esistere molte vetrine sullo stesso tema.

### Regole figlie (Opzione A)
- **Ereditano** le regole della vetrina madre.
- Il creator può **modificarle o aggiungerle**.

## 7) Inviti
- **Chiunque** può invitare altri.
- L’invito non cambia lo stato di accesso: valgono sempre le regole di ingaggio.

## 8) Tutela marchi e identità
- Vietata l’appropriazione di brand o identità ufficiali.
- Se un utente prova a creare una vetrina “ufficiale” senza titolo:
  - L’AI segnala.
  - Richiede un titolo neutro (es. “Discussione su Adidas”).

## 9) Segnali di qualità (no like)
Alternative ai like:
- **Bookmark/Save** (utile per l’utente).
- **Highlight** (segnalazione di qualità).
- **Verified info** (contenuti con alto 5W).

## 10) Modello dati (alto livello)
### Vetrina
- id, title, theme, tags
- creatorId
- rulesCore (fixed)
- rulesCustom (editable)
- parentVetrinaId (opzionale)
- visibility: public
- createdAt

### Partecipazione
- userId, vetrinaId
- status: active / warned / restricted / excluded
- warningsCount
- lastWarningAt

### Messaggi
- vetrinaId, userId, text, createdAt
- aiScore5W
- aiFlags (insulto, disinformazione, ecc.)

## 11) Roadmap MVP (fasi)
### Fase 1
- Feed vetrine pubbliche.
- Vetrina detail (lettura + accesso partecipanti).
- Regole + accettazione.
- Moderazione AI base.
- 5W visibile.

### Fase 2
- Vetrine figlie con suggerimenti AI.
- Materiali consigliati + AI supporto (riassunti, spiegazioni).
- Quiz opzionali.
- Sponsorizzazioni.

---

Questo documento è la base operativa per l’integrazione del modello Social “Vetrina” in Veil.
Sviluppo incrementale, senza rompere la fluidità di Veil Messaging/Chatting già esistente.
