# Veil Vetrina — Schema Dati Tecnico (v1.0)

Data: 2026-02-09

Obiettivo: definire le entità e i campi minimi per implementare la parte Social “Vetrina” in Veil.

## 1) Collezioni principali (Firestore)

### `vetrine`
Documento vetrina (pubblica):
- `id` (string, doc id)
- `title` (string)
- `theme` (string)
- `tags` (array<string>)
- `creatorId` (string)
- `createdAt` (timestamp)
- `parentVetrinaId` (string|null)
- `visibility` (string, `"public"`)
- `status` (string, `"active" | "paused" | "closed"`)
- `coreRules` (array<string>) // es. ["no_insults","no_discrimination","be_civil"]
- `ruleOptions` (map<string,bool>)
  - `cite_sources_5w`
  - `stay_on_topic`
  - `respect_expertise`
  - `no_spam`
- `guidelines` (array<string>) // suggerimenti non vincolanti
- `quizEnabled` (bool)
- `quizLink` (string|null)
- `rulesCoreVersion` (string, es. `"v1"`)
- `rulesCustom` (map)
  - `requirements` (array<string>) // es. “leggere X”
  - `materialsFree` (array<map>)   // {title,url}
  - `materialsPremium` (array<map>)// {title,url,provider}
  - `quizOptional` (bool)
  - `notes` (string)
- `coverTone` (string|null) // es. "amber","blue","green"
- `coverUrl` (string|null) // immagine/video hero (URL pubblico)
- `accessPolicy` (map)
  - `entryMode` (string) // "open"
- `counters` (map)
  - `visitors30d` (int)
  - `observers30d` (int)
  - `participants30d` (int)
  - `visitorsTotal` (int)
  - `observersTotal` (int)
  - `participantsTotal` (int)
- `ranking` (map)
  - `finalScore30d` (double)
  - `finalScoreTotal` (double)
  - `qualityScore30d` (double)
  - `massScore30d` (double)
  - `conversionScore30d` (double)
  - `explanation` (string) // testo sintetico visibile
  - `badges` (array<string>) // es. ["off-topic ricorrente","fonti scarse"]
  - `components` (map)
    - `quality` (string) // es. "Argomentata ma spesso off-topic"
    - `mass` (string) // es. "Molti visitatori, trend in crescita"
    - `conversion` (string) // es. "Poche richieste di accesso"
  - `formulaVersion` (string, es. "v1")

### `vetrine/{vetrinaId}/participants`
Ruoli e stato utente nella vetrina:
- `userId` (string, doc id)
- `status` (string, `"active" | "warned" | "restricted" | "excluded"`)
- `warningsCount` (int)
- `joinedAt` (timestamp|null)
- `lastWarningAt` (timestamp|null)

### `vetrine/{vetrinaId}/messages`
Messaggi della vetrina:
- `id` (string)
- `userId` (string)
- `text` (string)
- `createdAt` (timestamp)
- `ai` (map)
  - `score5w` (int 0..5)
  - `flags` (array<string>) // es. ["insult","hate","misinfo"]
  - `moderation` (string) // "ok" | "warned" | "blocked"
  - `reviewNote` (string|null)
- `meta` (map)
  - `editedAt` (timestamp|null)

### `vetrine/{vetrinaId}/invites`
Inviti alla vetrina:
- `id` (string)
- `inviterId` (string)
- `targetEmail` (string|null)
- `targetUserId` (string|null)
- `createdAt` (timestamp)
- `status` (string, `"sent" | "accepted" | "expired"`)

### `vetrina_suggestions`
Suggerimenti AI per vetrine figlie:
- `id` (string)
- `sourceVetrinaId` (string)
- `suggestedTitle` (string)
- `reason` (string) // es. “off-topic but high quality”
- `createdAt` (timestamp)
- `status` (string, `"pending" | "accepted" | "dismissed"`)

## 2) Modelli client (Dart)

### `Vetrina`
- id, title, theme, tags, creatorId, createdAt
- parentVetrinaId, visibility, status
- rulesCoreVersion, rulesCustom, accessPolicy

### `VetrinaParticipant`
- userId, status, warningsCount, lastWarningAt, joinedAt

### `VetrinaMessage`
- id, userId, text, createdAt, ai{score5w,flags,moderation,reviewNote}

### `VetrinaInvite`
- id, inviterId, targetEmail, targetUserId, createdAt, status

### `VetrinaSuggestion`
- id, sourceVetrinaId, suggestedTitle, reason, createdAt, status

## 3) Regole Core (non modificabili)
Implementate lato server o policy:
- no insults/hate/defamation
- no discrimination
- civility baseline

## 4) Policy AI (minimo)
- `score5w`: 0..5
- `flags`: hate, insult, spam, misinfo
- `moderation`: ok/warned/blocked

## 5) Note di integrazione
- Tutte le vetrine sono pubbliche.
- Chiunque può creare una vetrina (incluse figlie).
- Le regole della vetrina figlia **ereditano** quelle della madre (modificabili).
