#!/usr/bin/env python3
"""Regenerate doc/filemaker-import-analysis.html from the FileMaker NDJSON export.

Run from the project root:

    python3 docs/build_import_analysis.py

Reads:
  doc/w3emothe_T01_tituloEM.ndjson   two FileMaker tables (T00_indiceEM, T01_tituloEM)
  test/fixtures/**/*.xml             the TEI files we hold locally
Writes:
  doc/filemaker-import-analysis.html self-contained page, no external assets

Every count on the page comes from this script, so re-run it whenever the corpus
grows or a new export lands.
"""

import collections
import glob
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NDJSON = os.path.join(ROOT, "doc", "w3emothe_T01_tituloEM.ndjson")
OUT = os.path.join(ROOT, "doc", "filemaker-import-analysis.html")

# Plays already imported into emothe_dev. Refresh with:
#   psql -U postgres -h localhost -d emothe_dev -tAc \
#     "select split_part(code,'_',1)||' '||language||' '||coalesce(relationship_type,'-') from plays"
DB_PLAYS = {
    "EMOTHE0010": ("es", "adaptacion"),
    "EMOTHE0038": ("es", None),
    "EMOTHE0050": ("it", "traduccion"),
    "EMOTHE0052": ("es", "traduccion"),
    "EMOTHE0053": ("es", None),
    "EMOTHE0059": ("fr", "traduccion"),
    "EMOTHE0139": ("it", "traduccion"),
    "EMOTHE0703": ("es", "traduccion"),
}

LANG = {"1": "es", "2": "fr", "3": "en", "4": "it", "5": "pt"}


# --------------------------------------------------------------------------- load

def load():
    tables = collections.defaultdict(list)
    current = None
    for line in open(NDJSON, encoding="utf-8"):
        obj = json.loads(line)
        if "_meta" in obj:
            current = obj["_meta"]["layout"]
        elif "fields" in obj:
            tables[current].append(obj)
    return tables["T00_indiceEM"], tables["T01_tituloEM"]


def f(record, key):
    value = record["fields"].get(key)
    return ("\n".join(value) if isinstance(value, list) else (value or "")).strip()


def text(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()


def local_codes():
    """code -> filename stem, for every TEI file under test/fixtures."""
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "test/fixtures/**/*.xml"), recursive=True)):
        stem = os.path.basename(path)[:-4]
        out.setdefault(stem.split("_")[0], stem)
    return out


VERSION_LI = re.compile(
    r'<li>(?:<span[^>]*>\[(?P<lang>[A-Z]{2})\]\s*</span>)?\s*'
    r'<a href="textosEMOTHE/(?P<code>[A-Za-z0-9]+)_(?P<file>[^"]*)\.php"[^>]*>(?P<title>.*?)</a>'
    r'(?P<rest>.*?)</li>', re.S)


def parse_index(t0):
    """T00_indiceEM -> {code: version} and {work_id: [versions]}."""
    by_code, by_work = {}, {}
    for record in t0:
        work = f(record, "_IdIndiceCtce")
        versions = []
        for m in VERSION_LI.finditer(f(record, "pub_listaObras")):
            credit = text(m.group("rest")).replace("[xml]", "").strip()
            role = "ed" if re.search(r",\s*ed\.", credit) else ("tra" if re.search(r",\s*tra\.", credit) else None)
            versions.append(dict(
                code=m.group("code"), lang=(m.group("lang") or "").lower(),
                title=text(m.group("title")), credit=credit, role=role,
                xml="textosXML/%s_%s.xml" % (m.group("code"), m.group("file")),
                work=work))
        for v in versions:
            by_code[v["code"]] = v
        by_work[work] = dict(
            id=work, work=text(f(record, "pub_tituloOrden")), author=f(record, "bus_autor"),
            parallel=f(record, "bus_paralelo") == "1", versions=versions)
    return by_code, by_work


def index_t1(t1):
    """T01_tituloEM keyed by the code in its web-edition link."""
    out = {}
    for record in t1:
        m = re.search(r"textosEMOTHE/([A-Za-z0-9]+)_", f(record, "pub_edicionWeb"))
        code = m.group(1) if m else "EMOTHE%04d" % int(f(record, "_IdTituloEmothe"))
        out[code] = record
    return out


# ------------------------------------------------------------------- field catalogue
# (name, description, verdict, target, note, changed-since-CSV)

T1_FIELDS = [
 ("_IdTituloEmothe", "EMOTHE number of this version.", "join", "plays.code (leading token)",
  "Our plays.code is the whole filename stem, so join on split_part(code,'_',1). 26 rows are HIE####, not EMOTHE#### — take the code from the pub_edicionWeb href rather than formatting the number.", ""),
 ("_IdObraEmothe", "Work id. Groups the 439 versions into 198 works.", "join", "plays.parent_play_id + relationship_type",
  "Also the join to T00_indiceEM._IdIndiceCtce — validated on 152 works, zero title disagreements.", ""),
 ("pub_edicionWeb", "Link to the published web edition: <a href='../biblioteca/textosEMOTHE/HIE0393_TheSpanishBawd….php'>Enlace</a>.", "newfield", "plays.legacy_url (new) + authoritative code",
  "The CSV threw the href away and kept the word 'Enlace'. It is the only place the HIE#### codes appear.", "upgraded from Reject"),
 ("bus_personaje", "Dramatis personae, one character per line.", "ready", "characters (cross-check)",
  "In the CSV these were space-joined and unsplittable. Here they split cleanly on newlines. For plays we already imported from TEI, this is a completeness check rather than a source.", "upgraded from Flattened"),
 ("pub_testimonio", "Early witnesses as <ul><li> — one li per witness: <i>Title</i>. Author. City. Publisher. Year. Format. Notes.", "ready", "play_sources",
  "play_sources already has title/author/publisher/pub_place/pub_date. One regex per li fills the table.", "upgraded from Flattened"),
 ("pub_RepAntiguas", "Historical performances as <ul><li>, each with labelled <b>Company</b>, <b>Venue</b>, <b>Date</b>, <b>Cast</b> (nested ul, one li per actor), <b>Location</b>, <b>Venue type</b>, <b>Note</b>, <b>Information source</b>.", "newtable", "play_performances + cast (new)",
  "Fully structured. Mostly sourced from CATCOM and Wiggins' British Drama 1533-1642.", "upgraded from Flattened"),
 ("pub_EdModernas", "Modern critical editions, one <li> per edition, <i> marks the title.", "newtable", "play_bibliography (new), kind=modern_edition", "", ""),
 ("pub_BibSelectaCritica", "Selected criticism, one <li> per article: author, \"title\", journal, year, volume, pages.", "newtable", "play_bibliography, kind=criticism", "", ""),
 ("pub_BibSelectaTraduccion", "Selected translations, nested two levels: outer <li> is the target language (FR:, EN:, IT:, DE:), inner <ul><li> the citations.", "newtable", "play_bibliography, kind=translation + language",
  "The language per entry comes for free from the outer li.", ""),
 ("pub_BibSelectaAdaptacion", "Selected adaptations, one <li> each.", "newtable", "play_bibliography, kind=adaptation", "", ""),
 ("pub_TiemHistorico", "Historical time of the action: <li>Label<br/>Note: free commentary</li>.", "newfield", "plays.historical_time + historical_time_note (new)",
  "The <br/> splits label from note — no string heuristic needed. Notes are often a paragraph of real scholarship.", ""),
 ("bus_tiemHistorico", "Numeric code for the above. Vocabulary recovered by pairing with the text column: 1 indeterminado, 2 Antiguo Testamento, 5 Edad Media, 6 s.XV, 7 s.XVI, 8 s.XVII, 9 tiempo maravilloso, 10 Antigüedad clásica, 11 tiempo alegórico.", "ready", "controlled vocabulary for historical_time",
  "Codes 3 and 4 never occur in this export.", ""),
 ("pub_LugAccion", "Place of the action: '[España]. Europa.' then a prose description of the settings, with *** introducing an editorial note.", "newfield", "plays.place_of_action (new)", "", ""),
 ("pub_datacion", "Composition dating, one <li> per proposed dating: 'desde o posterior 1605 y anterior o hasta 1607', '1606'.", "newfield", "plays.composition_date (new)",
  "Several competing datings per play. Keep them as a list, don't collapse to one range.", ""),
 ("bus_coleccion", "Collection. Decoded from the published links: 1 = EMOTHE (358 rows, all languages), 2 = HIE (27 rows, English old-spelling quartos, HIE#### codes), 3 = 53 rows of modern-spelling English under EMOTHE codes.", "ready", "plays.collection (new)",
  "The CSV could not resolve this; the hrefs in this export do.", "upgraded from Needs codes"),
 ("pub_Titulo", "Title of this version.", "ready", "plays.title", "", ""),
 ("pub_TituloOrden", "Sort title, article moved to the end.", "ready", "plays.title_sort",
  "Field exists, TEI rarely carries it, 100% filled here.", ""),
 ("pub_TituloObra", "Title of the parent work.", "ready", "plays.original_title", "", ""),
 ("pub_Autor", "Author of the work, 'Surname, Name'.", "ready", "plays.author_name / author_sort", "Already in sort form.", ""),
 ("bus_idioma", "Language: 1=es 2=fr 3=en 4=it 5=pt, verified against the corpus.", "ready", "plays.language",
  "Our DB currently stores EMOTHE0038 (the English original) as 'es'. This column and the [EN] tags in T00 both fix that.", ""),
 ("bus_publicada", "Published flag, 61 rows = 1.", "ready", "plays.is_complete (review)",
  "Narrower than the 301 rows that actually have a web edition. Review before wiring it to the export gate.", ""),
 ("bus_edicionWeb", "Has-web-edition flag, 254 rows = 1.", "newfield", "plays.has_web_edition (new)",
  "Disagrees with pub_edicionWeb, which carries a real href on 301 rows. Trust the href.", ""),
 ("_kp_IdTituloEM", "FileMaker internal primary key.", "newfield", "plays.filemaker_id (new)",
  "Worth keeping only if you plan repeated syncs.", ""),
 ("bus_genero", "Genre code (5, 21, 20, 6, 8…).", "vocab", "plays.genre (new)",
  "Still no labels anywhere in either table. The one thing that genuinely needs another export.", ""),
 ("bus_generoAnnals", "Genre per Annals of English Drama, own code set.", "vocab", "plays.genre_annals (new)", "Needs the value list.", ""),
 ("bus_repCircunstancia", "Performance circumstance code.", "vocab", "play_performances.circumstance",
  "Needs the value list. The labelled Venue type inside pub_RepAntiguas covers part of the same ground in plain text.", ""),
 ("bus_autor", "Author of *this* version: the playwright on original rows, the adapter or translator on derived rows.", "review", "play_editors role=translator/adapter",
  "Same column, two meanings depending on the row. Import behind a review screen.", ""),
 ("pub_TituloWP", "WordPress slug of the old public page.", "reject", "—",
  "Re-checked in the JSON: still wrong on 50 of 95 rows — 'young-admiral' on JULES CÉSAR, 'shoemakers-holiday' on Sophonisba. A real FileMaker defect, not a CSV artefact.", "confirmed Reject"),
 ("bus_tradTraductor", "Translators, one per line.", "reject", "— (superseded)",
  "Correction to the CSV read: not corrupt, but a work-level roll-up of every translator of the work. pub_BibSelectaTraduccion carries the same names per citation, with the language.", "reason corrected"),
 ("bus_testCiudad", "Witness cities, one per line.", "reject", "— (superseded)",
  "Same data as pub_testimonio, unlabelled. Line counts agree with the <li> count on 75 of 105 rows, so use it as a cross-check only.", "was Flattened"),
 ("bus_testAnyo", "Witness years, one per line.", "reject", "— (superseded)", "", ""),
 ("bus_testFormato", "Witness format (4º, 2º), one per line.", "reject", "— (superseded)", "", ""),
 ("bus_testSoporte", "Witness support type, one per line.", "reject", "— (superseded)",
  "'ediciones antiguas, sueltas' is one value; this is the only place it appears, so keep it if you want source_type on play_sources.", ""),
 ("bus_repCompanyia", "Performing company, one per line.", "reject", "— (superseded)", "Inside pub_RepAntiguas as a labelled field.", ""),
 ("bus_repLugar", "Venue, one per line.", "reject", "— (superseded)", "", ""),
 ("bus_repAnyo", "Performance years.", "reject", "— (superseded)", "", ""),
 ("bus_repToponimo", "Performance place.", "reject", "— (superseded)", "", ""),
 ("bus_repReparto", "Historical cast.", "reject", "— (superseded)",
  "The nested <ul> under <b>Cast</b> in pub_RepAntiguas has the same names, per performance.", ""),
 ("bus_criticaAnyo", "Years of the criticism entries.", "reject", "— (superseded)", "", ""),
 ("bus_tradAnyo", "Years of the translation entries.", "reject", "— (superseded)", "", ""),
 ("bus_tradIdioma", "Target-language codes of the translations.", "reject", "— (superseded)",
  "The FR:/EN:/IT:/DE: headers in pub_BibSelectaTraduccion say the same thing in words.", ""),
 ("bus_lugAccion", "Place of action exploded into multilingual search keywords.", "reject", "—", "Search-index artefact of the old site.", ""),
 ("bus_datacion", "Machine dating.", "reject", "—", "Two rows still contain '[Error_CL] | Return error…'. Use pub_datacion.", ""),
 ("bus_titulo", "Search-normalised duplicate of pub_Titulo.", "reject", "—", "", ""),
 ("bus_anotada", "Annotated flag.", "reject", "—", "1 row, the ZZZ_OBRA_DE_PRUEBA test record.", ""),
 ("bus_cotejada", "Collated flag.", "reject", "—", "1 row, test record.", ""),
 ("pub_edicionAnotada", "Annotated edition.", "reject", "—", "1 row, test record.", ""),
 ("pub_edicionCotejada", "Collated edition.", "reject", "—", "1 row, test record.", ""),
]

T0_FIELDS = [
 ("pub_listaObras", "The published version list of the work, as HTML: per version a language tag [ES]/[EN]/[FR]/[IT]/[PT], the play page link carrying the code, the title, the credit with its role (ed. / tra.), and a direct download link to the TEI file.", "join", "plays.code, language, relationship_type, editors",
  "The richest single field in either table, and the whole basis of slice 1.", "new in JSON"),
 ("_IdIndiceCtce", "Work id in the CTCE numbering.", "join", "joins T01_tituloEM._IdObraEmothe",
  "Validated: 152 works matched, zero title disagreements. _kp_IdIndiceEM is not the key — 3 agreements out of 144.", "new in JSON"),
 ("bus_autor", "Author of the work.", "ready", "plays.author_name", "", ""),
 ("pub_tituloOrden", "Sort title of the work.", "ready", "plays.title_sort on the family head", "", ""),
 ("bus_traductor", "Every translator of the work, one per line, given-name first.", "ready", "play_editors role=translator",
  "Order follows the version order in pub_listaObras, so a translator can be attached to the right code.", ""),
 ("bus_autorAdaptacion", "The same people in sort form ('Hugo, François-Victor').", "ready", "play_editors.person_name (sort form)",
  "Pair with bus_traductor to get both display and sort forms of the name.", ""),
 ("bus_paralelo", "Parallel-view flag: 49 works have a side-by-side visualisation on the old site.", "newfield", "plays.has_parallel_view (new)",
  "Maps onto our existing /admin/plays/:id/compare feature — these are the families researchers already read side by side.", ""),
 ("bus_titulo", "Titles of all versions, one per line.", "reject", "— (superseded)", "Same list as pub_listaObras, without the codes.", ""),
 ("_kp_IdIndiceEM", "FileMaker internal primary key of the index record.", "reject", "—",
  "Not the join key — it agrees with _IdObraEmothe on only 3 of 144 rows.", ""),
]


# ------------------------------------------------------------------------ slices

def build_slices(mine_t1, ours_indexed, families, complete_families, li_counts, personaje_plays, corrections):
    def n(field):
        return sum(1 for r in mine_t1 if f(r, field))

    return [
      dict(id="S0", name="Corpus baseline", status="prerequisite",
           goal="Import the 82 TEI files under test/fixtures into the database so every later slice has something to attach to.",
           source="the files themselves, no FileMaker data",
           target="plays, characters, divisions, elements",
           plays=82, records=82,
           notes="14 filenames appear in both test/fixtures/ and test/fixtures/tei_files/; dedupe by code. Today the database holds 8 plays."),
      dict(id="S1", name="Work families & language", status="first",
           goal="Give every imported play its correct language, its relationship_type, and a parent_play_id inside its work family — read from the published index rather than guessed from the TEI.",
           source="T00_indiceEM.pub_listaObras",
           target="plays.language, relationship_type, parent_play_id, original_title",
           plays=ours_indexed, records=families,
           notes="%d of our codes are in the index, spread over %d work families; we hold every published version of %d of them. %d of the 8 plays now in the database have a wrong language or relationship. The relationship UI (admin combobox, catalogue grouping, compare view) already exists and lights up as soon as the data lands." % (ours_indexed, families, complete_families, corrections)),
      dict(id="S2", name="Version metadata panel", status="next",
           goal="Add the research metadata that has no home in TEI: historical time of the action and its note, place of action, composition dating, collection, and the legacy web-edition URL.",
           source="T01: pub_TiemHistorico, pub_LugAccion, pub_datacion, bus_coleccion, pub_edicionWeb",
           target="new columns on plays + admin form + public play page",
           plays=len(mine_t1), records=li_counts["pub_datacion"],
           notes="Applies to the %d plays that have a T01 research record: %d have a historical time, %d a place of action, %d a dating." % (len(mine_t1), n("pub_TiemHistorico"), n("pub_LugAccion"), n("pub_datacion"))),
      dict(id="S3", name="Witnesses (testimonios)", status="later",
           goal="Fill play_sources with the early editions and manuscripts each play survives in.",
           source="T01.pub_testimonio, one <li> per witness",
           target="play_sources (+ source_type, format columns)",
           plays=n("pub_testimonio"), records=li_counts["pub_testimonio"],
           notes="The existing play_sources columns already match the shape: title, author, pub_place, publisher, pub_date. bus_testSoporte adds the support type."),
      dict(id="S4", name="Bibliography", status="later",
           goal="One table for the four selected bibliographies: modern editions, criticism, translations, adaptations.",
           source="T01.pub_EdModernas, pub_BibSelectaCritica / Traduccion / Adaptacion",
           target="play_bibliography (new)",
           plays=max(n("pub_EdModernas"), n("pub_BibSelectaCritica")),
           records=li_counts["pub_EdModernas"] + li_counts["pub_BibSelectaCritica"] + li_counts["pub_BibSelectaTraduccion"] + li_counts["pub_BibSelectaAdaptacion"],
           notes="The translation list nests citations under a language header, so each entry keeps its language."),
      dict(id="S5", name="Historical performances", status="later",
           goal="Record documented early performances: company, venue, date, cast, venue type, source.",
           source="T01.pub_RepAntiguas",
           target="play_performances + play_performance_cast (new)",
           plays=n("pub_RepAntiguas"), records=li_counts["pub_RepAntiguas"],
           notes="Labelled fields inside each <li>, cast as a nested list. Sources are CATCOM and Wiggins."),
      dict(id="S6", name="Character reconciliation", status="later",
           goal="Compare the FileMaker dramatis personae against the characters our TEI import produced, and flag the differences for review.",
           source="T01.bus_personaje, one name per line",
           target="a review screen over characters",
           plays=personaje_plays, records=0,
           notes="Not an import: TEI is the source of truth for characters. This is a completeness check, and it feeds the 'review character in text' UI already on the roadmap."),
      dict(id="S7", name="Editor & translator credits", status="later",
           goal="Cross-check play_editors against the credits printed in the index ('Tronch, Jesús, ed.', 'Hugo, François-Victor, tra.').",
           source="T00.pub_listaObras credits, bus_traductor, bus_autorAdaptacion",
           target="play_editors",
           plays=ours_indexed, records=ours_indexed,
           notes="Same parse as slice 1; kept separate so slice 1 stays small. bus_autorAdaptacion gives the sort form of each name."),
      dict(id="S8", name="Genre", status="blocked",
           goal="Genre facets on the catalogue, as the old public site had.",
           source="T01.bus_genero, bus_generoAnnals",
           target="plays.genre, plays.genre_annals",
           plays=n("bus_genero"), records=0,
           notes="Blocked: the codes have no labels in either table. Needs the FileMaker value lists — the only outstanding request."),
    ]


# --------------------------------------------------------------------------- build

def main():
    t0, t1 = load()
    idx, works = parse_index(t0)
    t1_by_code = index_t1(t1)
    ours = local_codes()

    ours_indexed = sorted(c for c in ours if c in idx)
    mine_t1 = [t1_by_code[c] for c in ours if c in t1_by_code]
    fam_ids = {idx[c]["work"] for c in ours_indexed}
    complete = [w for w in fam_ids if all(v["code"] in ours for v in works[w]["versions"])]

    li_counts = {}
    for field in ("pub_testimonio", "pub_EdModernas", "pub_BibSelectaCritica",
                  "pub_BibSelectaTraduccion", "pub_BibSelectaAdaptacion",
                  "pub_RepAntiguas", "pub_datacion"):
        li_counts[field] = sum(len(re.findall(r"<li>", f(r, field))) for r in mine_t1)

    # concrete corrections the first slice makes to the 8 plays already imported
    corrections = []
    for code, (lang, rel) in sorted(DB_PLAYS.items()):
        v = idx.get(code)
        if not v:
            continue
        want_rel = None if v["role"] == "ed" else "traduccion"
        fixes = []
        if v["lang"] and v["lang"] != lang:
            fixes.append("language %s → %s" % (lang, v["lang"]))
        if (rel or None) != want_rel:
            fixes.append("relationship %s → %s" % (rel or "—", want_rel or "— (original)"))
        corrections.append(dict(code=code, title=v["title"], lang=v["lang"], role=v["role"],
                                work=v["work"], fixes=fixes))

    def field_rows(records, spec, table, mine):
        rows = []
        total = len(records)
        for name, desc, verdict, target, note, changed in spec:
            values = [f(r, name) for r in records if f(r, name)]
            mine_filled = sum(1 for r in mine if f(r, name))
            samples = sorted(set(values), key=lambda v: (len(v) > 600, -len(v)))[:2]
            samples = [(s[:500] + "…" if len(s) > 500 else s) for s in samples]
            rows.append(dict(name=name, table=table, desc=desc, verdict=verdict, target=target,
                             note=note, changed=changed, filled=len(values),
                             pct=round(100 * len(values) / total, 1), uniq=len(set(values)),
                             mine=mine_filled, mineOf=len(mine), samples=samples))
        return rows

    mine_t0 = [r for r in t0 if any(v["code"] in ours for v in works[f(r, "_IdIndiceCtce")]["versions"])]
    fields = (field_rows(t1, T1_FIELDS, "T01_tituloEM", mine_t1) +
              field_rows(t0, T0_FIELDS, "T00_indiceEM", mine_t0))

    work_cards = []
    for wid in sorted(works, key=lambda w: (-sum(1 for v in works[w]["versions"] if v["code"] in ours),
                                            -len(works[w]["versions"]), works[w]["work"])):
        w = works[wid]
        versions = [dict(v, have=v["code"] in ours, db=v["code"] in DB_PLAYS,
                         meta=v["code"] in t1_by_code) for v in w["versions"]]
        work_cards.append(dict(id=wid, work=w["work"], author=w["author"], parallel=w["parallel"],
                               n=len(versions), have=sum(1 for v in versions if v["have"]),
                               db=sum(1 for v in versions if v["db"]),
                               complete=all(v["have"] for v in versions), titles=versions))

    data = dict(
        t0=len(t0), t1=len(t1), works=len(works),
        versions=sum(len(w["versions"]) for w in works.values()), codes=len(idx),
        local=len(ours), localAl=len([c for c in ours if c.startswith("AL")]),
        oursIndexed=len(ours_indexed), oursMeta=len(mine_t1),
        families=len(fam_ids), complete=len(complete), db=len(DB_PLAYS),
        parallel=sum(1 for w in works.values() if w["parallel"]),
        corrections=corrections,
        slices=build_slices(mine_t1, len(ours_indexed), len(fam_ids), len(complete), li_counts,
                            sum(1 for r in mine_t1 if f(r, "bus_personaje")),
                            sum(1 for c in corrections if c["fixes"])),
        fields=fields, worksList=work_cards,
        verdictCounts=collections.Counter(x["verdict"] for x in fields),
        tableCounts=collections.Counter(x["table"] for x in fields),
    )

    payload = json.dumps(data, ensure_ascii=False).replace("</script>", "<\\/script>")
    open(OUT, "w", encoding="utf-8").write(TEMPLATE.replace("__DATA__", payload))
    print("wrote %s (%d KB)" % (OUT, os.path.getsize(OUT) // 1024))
    print("  local corpus %d codes (%d Artelope), %d in the index, %d with research metadata"
          % (len(ours), data["localAl"], data["oursIndexed"], data["oursMeta"]))
    print("  %d families touched, %d held complete, %d of %d DB plays need a correction"
          % (data["families"], data["complete"], sum(1 for c in corrections if c["fixes"]), len(DB_PLAYS)))


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EMOTHE — FileMaker import, sliced by feature</title>
<style>
  :root {
    color-scheme: light;
    --surface-1: #fcfcfb; --plane: #f9f9f7; --ink: #0b0b0b; --ink-2: #52514e; --muted: #898781;
    --grid: #e1e0d9; --rule: #c3c2b7; --ring: rgba(11,11,11,0.10);
    --bar: #2a78d6; --bar-bg: #cde2fb;
    --good: #0ca30c; --warning: #fab219; --serious: #ec835a; --critical: #d03b3b;
    --join: #2a78d6; --newfield: #1baf7a; --newtable: #4a3aa7;
  }
  @media (prefers-color-scheme: dark) {
    :root:where(:not([data-theme="light"])) {
      color-scheme: dark;
      --surface-1: #1a1a19; --plane: #0d0d0d; --ink: #ffffff; --ink-2: #c3c2b7; --muted: #898781;
      --grid: #2c2c2a; --rule: #383835; --ring: rgba(255,255,255,0.10);
      --bar: #3987e5; --bar-bg: #184f95; --join: #3987e5; --newfield: #199e70; --newtable: #9085e9;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--plane); color: var(--ink); font: 15px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
  .wrap { max-width: 1120px; margin: 0 auto; padding: 32px 20px 96px; }
  h1 { font-size: 26px; line-height: 1.2; margin: 0 0 8px; }
  h2 { font-size: 18px; margin: 40px 0 12px; }
  h3 { font-size: 15px; margin: 24px 0 8px; }
  p { margin: 0 0 12px; color: var(--ink-2); max-width: 78ch; }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; background: var(--surface-1); border: 1px solid var(--ring); border-radius: 4px; padding: 1px 4px; }
  .sub { color: var(--muted); font-size: 13px; margin-bottom: 24px; }

  .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin: 20px 0 8px; }
  .tile { background: var(--surface-1); border: 1px solid var(--ring); border-radius: 10px; padding: 14px 16px; }
  .tile .v { font-size: 30px; font-weight: 650; letter-spacing: -0.02em; }
  .tile .k { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; margin-top: 2px; }
  .tile .n { font-size: 12px; color: var(--ink-2); margin-top: 6px; }

  .callout { background: var(--surface-1); border: 1px solid var(--ring); border-left: 3px solid var(--bar); border-radius: 8px; padding: 14px 16px; margin: 20px 0; }
  .callout p:last-child { margin-bottom: 0; }
  .callout.warn { border-left-color: var(--warning); }
  .callout.good { border-left-color: var(--good); }

  .chain { display: grid; margin: 16px 0; font-size: 13.5px; }
  .chain .step { background: var(--surface-1); border: 1px solid var(--ring); border-radius: 8px; padding: 10px 13px; }
  .chain .arrow { color: var(--muted); font-size: 12px; padding: 5px 0 5px 14px; }
  .chain .step b { font-family: ui-monospace, Menlo, monospace; font-size: 12.5px; font-weight: 600; }
  .chain .step .v { color: var(--muted); font-size: 12px; display: block; margin-top: 3px; }

  .tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--grid); margin: 32px 0 20px; flex-wrap: wrap; }
  .tabs button { appearance: none; background: none; border: 0; border-bottom: 2px solid transparent; color: var(--ink-2); font: inherit; padding: 9px 14px; cursor: pointer; }
  .tabs button[aria-selected="true"] { color: var(--ink); border-bottom-color: var(--bar); font-weight: 600; }
  .tabs button:hover { color: var(--ink); }
  .panel[hidden] { display: none; }

  .controls { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 14px; }
  input[type="search"] { flex: 1 1 220px; min-width: 180px; background: var(--surface-1); color: var(--ink); border: 1px solid var(--rule); border-radius: 8px; padding: 8px 11px; font: inherit; }
  .chip { appearance: none; background: var(--surface-1); color: var(--ink-2); border: 1px solid var(--rule); border-radius: 999px; padding: 5px 11px; font: inherit; font-size: 13px; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; }
  .chip[aria-pressed="true"] { color: var(--ink); border-color: var(--ink-2); font-weight: 600; }
  .chip .dot { width: 8px; height: 8px; border-radius: 2px; display: inline-block; }
  .chip .ct { color: var(--muted); font-variant-numeric: tabular-nums; }
  .lbl { font-size: 13px; color: var(--muted); }

  .slice { background: var(--surface-1); border: 1px solid var(--ring); border-radius: 10px; padding: 14px 16px; margin-bottom: 12px; display: grid; grid-template-columns: 62px 1fr; gap: 14px; }
  .slice .id { font-family: ui-monospace, Menlo, monospace; font-size: 20px; font-weight: 650; color: var(--muted); }
  .slice h3 { margin: 0 0 4px; font-size: 16px; }
  .slice p { margin: 0 0 10px; font-size: 14px; }
  .slice dl { display: grid; grid-template-columns: max-content 1fr; gap: 3px 12px; margin: 0 0 10px; font-size: 13px; }
  .slice dt { color: var(--muted); }
  .slice dd { margin: 0; color: var(--ink-2); font-family: ui-monospace, Menlo, monospace; font-size: 12px; }
  .slice .foot { font-size: 13px; color: var(--ink-2); border-top: 1px solid var(--grid); padding-top: 8px; }
  .stat { display: inline-flex; gap: 6px; align-items: baseline; margin-right: 14px; font-size: 13px; }
  .stat b { font-size: 17px; font-weight: 650; }
  .status { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; padding: 2px 8px 2px 6px; border-radius: 999px; border: 1px solid var(--ring); }
  .status[data-s="prerequisite"] { box-shadow: inset 3px 0 0 var(--muted); }
  .status[data-s="first"] { box-shadow: inset 3px 0 0 var(--good); }
  .status[data-s="next"] { box-shadow: inset 3px 0 0 var(--join); }
  .status[data-s="later"] { box-shadow: inset 3px 0 0 var(--newtable); }
  .status[data-s="blocked"] { box-shadow: inset 3px 0 0 var(--warning); }

  table { width: 100%; border-collapse: collapse; background: var(--surface-1); border: 1px solid var(--ring); border-radius: 10px; }
  .tscroll { overflow-x: auto; }
  th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--muted); font-weight: 600; padding: 10px 12px; border-bottom: 1px solid var(--grid); white-space: nowrap; }
  td { padding: 10px 12px; border-bottom: 1px solid var(--grid); vertical-align: top; }
  tr.row { cursor: pointer; }
  tr.row:hover td { background: color-mix(in srgb, var(--bar) 6%, transparent); }
  tr.detail > td { background: color-mix(in srgb, var(--muted) 8%, transparent); }
  .fname { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12.5px; white-space: nowrap; }
  .fname .tb { display: block; font-family: system-ui, sans-serif; font-size: 10.5px; color: var(--muted); margin-top: 2px; }
  .tgt { font-size: 13px; }
  .desc { font-size: 13px; color: var(--ink-2); max-width: 44ch; }

  .badge { display: inline-flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 600; white-space: nowrap; padding: 2px 8px 2px 6px; border-radius: 999px; border: 1px solid var(--ring); background: var(--surface-1); color: var(--ink); }
  .badge[data-v="join"] { box-shadow: inset 3px 0 0 var(--join); }
  .badge[data-v="ready"] { box-shadow: inset 3px 0 0 var(--good); }
  .badge[data-v="newfield"] { box-shadow: inset 3px 0 0 var(--newfield); }
  .badge[data-v="newtable"] { box-shadow: inset 3px 0 0 var(--newtable); }
  .badge[data-v="vocab"] { box-shadow: inset 3px 0 0 var(--warning); }
  .badge[data-v="review"] { box-shadow: inset 3px 0 0 var(--serious); }
  .badge[data-v="reject"] { box-shadow: inset 3px 0 0 var(--critical); }
  .chg { display: inline-block; font-size: 11px; color: var(--ink-2); border: 1px dashed var(--rule); border-radius: 999px; padding: 1px 7px; margin-top: 4px; white-space: nowrap; }

  .bar { display: flex; align-items: center; gap: 8px; }
  .bar .track { width: 74px; height: 8px; background: var(--bar-bg); border-radius: 4px; overflow: hidden; }
  .bar .fill { height: 100%; background: var(--bar); border-radius: 4px; }
  .bar .pct { font-size: 12.5px; font-variant-numeric: tabular-nums; color: var(--ink-2); min-width: 6ch; }
  .mine { font-size: 12.5px; font-variant-numeric: tabular-nums; color: var(--ink-2); white-space: nowrap; }

  .samples { margin: 0; font-size: 13px; color: var(--ink-2); padding-left: 18px; }
  .samples li { margin-bottom: 6px; }
  .samples code { display: block; padding: 7px 9px; white-space: pre-wrap; word-break: break-word; }
  .note { font-size: 13px; color: var(--ink-2); margin: 8px 0 0; }

  .works { display: grid; gap: 10px; }
  .work { background: var(--surface-1); border: 1px solid var(--ring); border-radius: 10px; padding: 12px 14px; }
  .work h4 { margin: 0 0 2px; font-size: 15px; }
  .work .meta { font-size: 12px; color: var(--muted); margin-bottom: 8px; }
  .t { display: flex; gap: 8px; align-items: baseline; font-size: 13px; padding: 3px 0; border-top: 1px solid var(--grid); flex-wrap: wrap; }
  .t .c { font-family: ui-monospace, Menlo, monospace; font-size: 12px; color: var(--muted); min-width: 11ch; }
  .t .tt { flex: 1 1 320px; }
  .t .au { color: var(--muted); font-size: 12px; }
  .pill { font-size: 11px; font-weight: 600; padding: 1px 6px; border-radius: 999px; border: 1px solid var(--ring); color: var(--ink-2); white-space: nowrap; }
  .pill.db { border-color: var(--good); color: var(--ink); box-shadow: inset 3px 0 0 var(--good); }
  .pill.have { border-color: var(--rule); color: var(--ink); box-shadow: inset 3px 0 0 var(--bar); }
  .pill.fix { box-shadow: inset 3px 0 0 var(--serious); color: var(--ink); }
  .lang { font-family: ui-monospace, Menlo, monospace; font-size: 11px; color: var(--ink-2); border: 1px solid var(--ring); border-radius: 4px; padding: 0 4px; }
  ul.plan { color: var(--ink-2); max-width: 78ch; padding-left: 20px; }
  ul.plan li { margin-bottom: 8px; }
  footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid var(--grid); font-size: 12px; color: var(--muted); }
</style>
</head>
<body>
<div class="wrap">
  <h1>FileMaker import, sliced by feature</h1>
  <p class="sub">Source: <code>doc/w3emothe_T01_tituloEM.ndjson</code> — <code>T00_indiceEM</code> (203 works) and <code>T01_tituloEM</code> (439 versions), pulled from the FileMaker Data API. Regenerate with <code>python3 docs/build_import_analysis.py</code>.</p>

  <p><strong>Scope: only plays we already hold.</strong> The export describes 379 published plays; we have TEI for 82 of them on disk and 8 imported. Every slice below is measured against <em>our</em> corpus, not the whole archive — the last two columns of the field table show the difference.</p>

  <div class="tiles" id="tiles"></div>

  <div class="callout">
    <p><strong>What our corpus can actually receive.</strong> Of 82 local codes, 19 are Artelope (<code>AL####</code>) and appear nowhere in this export. 62 are in the published index, so they get language, family and credits. Only 22 have a <code>T01</code> research record, so the metadata, bibliography, witness and performance slices are bounded by that number — which is why they come after the index slice.</p>
  </div>

  <div class="tabs" role="tablist">
    <button role="tab" aria-selected="true" data-tab="slices">Feature slices</button>
    <button role="tab" aria-selected="false" data-tab="fix">What slice 1 changes</button>
    <button role="tab" aria-selected="false" data-tab="fields">Field-by-field</button>
    <button role="tab" aria-selected="false" data-tab="works">Work families</button>
  </div>

  <section class="panel" id="panel-slices">
    <div id="slices"></div>
    <h2>How it joins</h2>
    <div class="chain" id="chain"></div>
  </section>

  <section class="panel" id="panel-fix" hidden>
    <p>The 8 plays currently in <code>emothe_dev</code>, checked against the published index. Three of them are wrong today: the TEI header's <code>xml:lang</code> is always <code>es</code> in EMOTHE files (it marks the editorial platform, not the play), so the importer stored Hamlet's English original as Spanish.</p>
    <div id="fix"></div>
    <p class="note">Everything else in the corpus — the other 54 indexed plays — gets its language and relationship set on first import rather than corrected.</p>
  </section>

  <section class="panel" id="panel-fields" hidden>
    <div class="controls" id="chips"></div>
    <div class="controls" id="tablechips"></div>
    <div class="controls">
      <input type="search" id="q" placeholder="Search field name, description or target…" aria-label="Search fields">
      <span class="lbl" id="count"></span>
    </div>
    <div class="tscroll">
      <table>
        <thead><tr><th>Field</th><th>Filled (whole export)</th><th>Our plays</th><th>Verdict</th><th>Goes to</th><th>What it is</th></tr></thead>
        <tbody id="tbody"></tbody>
      </table>
    </div>
    <p class="note">Click a row for real sample values and the caveat. "Our plays" counts only the records that match a TEI file we hold. A dashed pill marks a verdict that changed when the JSON replaced the CSV.</p>
  </section>

  <section class="panel" id="panel-works" hidden>
    <p>Every work in the index, with the versions we hold marked. A family we hold completely can be linked end to end; a partial one still gets its <code>relationship_type</code> and <code>original_title</code>, with <code>parent_play_id</code> left null until the original is imported.</p>
    <div class="controls">
      <input type="search" id="wq" placeholder="Search work, title, code or author…" aria-label="Search works">
      <button class="chip" id="whave" aria-pressed="true">Only families we touch</button>
      <button class="chip" id="wfull" aria-pressed="false">Only families we hold completely</button>
      <button class="chip" id="wdb" aria-pressed="false">Only what is in the DB</button>
      <span class="lbl" id="wcount"></span>
    </div>
    <div class="works" id="works"></div>
    <p class="note" id="wmore"></p>
  </section>

  <footer>Counts computed from the NDJSON export, <code>test/fixtures/**/*.xml</code> and the play list in <code>emothe_dev</code>. Plans: <code>docs/superpowers/plans/</code>.</footer>
</div>

<script id="data" type="application/json">__DATA__</script>
<script>
const D = JSON.parse(document.getElementById('data').textContent);
const esc = s => String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

const V = {
  join:     {label: 'Join key',    glyph: '⚭'},
  ready:    {label: 'Import now',  glyph: '✓'},
  newfield: {label: 'New column',  glyph: '+'},
  newtable: {label: 'New table',   glyph: '▤'},
  vocab:    {label: 'Needs codes', glyph: '?'},
  review:   {label: 'Needs review',glyph: '!'},
  reject:   {label: 'Reject',      glyph: '✕'},
};
const ORDER = ['join','ready','newfield','newtable','vocab','review','reject'];
const HUE = {join:'join', ready:'good', newfield:'newfield', newtable:'newtable', vocab:'warning', review:'serious', reject:'critical'};

document.getElementById('tiles').innerHTML = [
  [D.local, 'TEI files we hold', D.localAl + ' of them Artelope, absent from this export'],
  [D.oursIndexed, 'covered by the index', D.families + ' work families, ' + D.complete + ' of them held complete'],
  [D.oursMeta, 'with research metadata', 'the ceiling for the metadata, bibliography and performance slices'],
  [D.db, 'imported so far', D.corrections.filter(c => c.fixes.length).length + ' of them wrong today'],
].map(([v,k,n]) => `<div class="tile"><div class="v">${v}</div><div class="k">${k}</div><div class="n">${n}</div></div>`).join('');

document.getElementById('slices').innerHTML = D.slices.map(s => `
  <div class="slice">
    <div class="id">${s.id}</div>
    <div>
      <h3>${esc(s.name)} <span class="status" data-s="${s.status}">${s.status}</span></h3>
      <p>${esc(s.goal)}</p>
      <dl>
        <dt>from</dt><dd>${esc(s.source)}</dd>
        <dt>into</dt><dd>${esc(s.target)}</dd>
      </dl>
      <div style="margin-bottom:8px">
        <span class="stat"><b>${s.plays}</b> plays</span>
        ${s.records ? `<span class="stat"><b>${s.records}</b> records</span>` : ''}
      </div>
      <div class="foot">${esc(s.notes)}</div>
    </div>
  </div>`).join('');

document.getElementById('chain').innerHTML = [
  ['T00_indiceEM.pub_listaObras', 'one <li> per published version: [ES]/[EN]/[FR]/[IT]/[PT], the code, the title, the credit with its role, the TEI download path'],
  ['→ code, e.g. EMOTHE0053', 'also in T01 via the pub_edicionWeb href. 27 versions are HIE####, not EMOTHE#### — never format the number yourself'],
  ["= split_part(plays.code, '_', 1)", 'our plays.code is the full filename stem, so match on the leading token'],
  ['T00._IdIndiceCtce = T01._IdObraEmothe', 'the work family, validated on 152 works with zero title disagreements'],
].map(([a,b],i) => `${i ? '<div class="arrow">↓</div>' : ''}<div class="step"><b>${esc(a)}</b><span class="v">${esc(b)}</span></div>`).join('');

document.getElementById('fix').innerHTML = '<div class="works">' + D.corrections.map(c => `
  <div class="work">
    <h4><span class="c" style="font-family:ui-monospace,Menlo,monospace">${c.code}</span> ${esc(c.title)}</h4>
    <div class="meta">index says <span class="lang">${c.lang}</span> · credited as <code>${c.role || '—'}</code> · work ${c.work}</div>
    ${c.fixes.length
      ? c.fixes.map(x => `<div class="t"><span class="pill fix">fix</span><span class="tt">${esc(x)}</span></div>`).join('')
      : '<div class="t"><span class="pill">no change</span><span class="tt">language and relationship already correct</span></div>'}
  </div>`).join('') + '</div>';

const active = new Set(), activeT = new Set();
document.getElementById('chips').innerHTML = ORDER.map(v =>
  `<button class="chip" data-v="${v}" aria-pressed="false">
     <span class="dot" style="background:var(--${HUE[v]})"></span>${V[v].glyph} ${V[v].label}
     <span class="ct">${D.verdictCounts[v] || 0}</span></button>`).join('');
document.querySelectorAll('#chips .chip').forEach(b => b.onclick = () => {
  active.has(b.dataset.v) ? active.delete(b.dataset.v) : active.add(b.dataset.v);
  b.setAttribute('aria-pressed', active.has(b.dataset.v));
  renderFields();
});
document.getElementById('tablechips').innerHTML = Object.keys(D.tableCounts).map(t =>
  `<button class="chip" data-t="${t}" aria-pressed="false">${t} <span class="ct">${D.tableCounts[t]}</span></button>`).join('');
document.querySelectorAll('#tablechips .chip').forEach(b => b.onclick = () => {
  activeT.has(b.dataset.t) ? activeT.delete(b.dataset.t) : activeT.add(b.dataset.t);
  b.setAttribute('aria-pressed', activeT.has(b.dataset.t));
  renderFields();
});

function renderFields() {
  const q = document.getElementById('q').value.toLowerCase();
  const list = D.fields.filter(f =>
    (!active.size || active.has(f.verdict)) && (!activeT.size || activeT.has(f.table)) &&
    (!q || (f.name + ' ' + f.desc + ' ' + f.target + ' ' + f.note).toLowerCase().includes(q)));
  list.sort((a, b) => ORDER.indexOf(a.verdict) - ORDER.indexOf(b.verdict) || b.mine - a.mine || b.pct - a.pct);
  document.getElementById('count').textContent = list.length + ' of ' + D.fields.length + ' columns';
  document.getElementById('tbody').innerHTML = list.map((f, i) => `
    <tr class="row" data-i="${i}">
      <td class="fname">${esc(f.name)}<span class="tb">${f.table}</span></td>
      <td><div class="bar" title="${f.filled} rows"><div class="track"><div class="fill" style="width:${f.pct}%"></div></div><span class="pct">${f.pct}%</span></div></td>
      <td class="mine">${f.mine} / ${f.mineOf}</td>
      <td><span class="badge" data-v="${f.verdict}">${V[f.verdict].glyph} ${V[f.verdict].label}</span>
        ${f.changed ? `<br><span class="chg">${esc(f.changed)}</span>` : ''}</td>
      <td class="tgt">${esc(f.target)}</td>
      <td class="desc">${esc(f.desc)}</td>
    </tr>
    <tr class="detail" id="d${i}" hidden><td colspan="6">
      ${f.samples.length ? '<ul class="samples">' + f.samples.map(s => `<li><code>${esc(s)}</code></li>`).join('') + '</ul>' : '<p class="note">No values in this export.</p>'}
      ${f.note ? `<p class="note"><strong>${V[f.verdict].label}:</strong> ${esc(f.note)}</p>` : ''}
    </td></tr>`).join('');
  document.querySelectorAll('#tbody tr.row').forEach(r => r.onclick = () => {
    const d = document.getElementById('d' + r.dataset.i);
    d.hidden = !d.hidden;
  });
}
document.getElementById('q').oninput = renderFields;
renderFields();

const F = {have: document.getElementById('whave'), full: document.getElementById('wfull'), db: document.getElementById('wdb')};
Object.values(F).forEach(b => b.onclick = () => {
  b.setAttribute('aria-pressed', b.getAttribute('aria-pressed') !== 'true');
  renderWorks();
});
const on = b => b.getAttribute('aria-pressed') === 'true';
function renderWorks() {
  const q = document.getElementById('wq').value.toLowerCase();
  const list = D.worksList.filter(w =>
    (!on(F.have) || w.have) && (!on(F.full) || (w.complete && w.have)) && (!on(F.db) || w.db) &&
    (!q || (w.work + ' ' + w.author + ' ' + w.titles.map(t => t.code + ' ' + t.title + ' ' + t.credit).join(' ')).toLowerCase().includes(q)));
  document.getElementById('wcount').textContent = list.length + ' of ' + D.worksList.length + ' works';
  const shown = list.slice(0, 50);
  document.getElementById('works').innerHTML = shown.map(w => `
    <div class="work">
      <h4>${esc(w.work)}
        ${w.have ? `<span class="pill have">${w.have} of ${w.n} held</span>` : ''}
        ${w.complete && w.have ? '<span class="pill db">complete family</span>' : ''}
        ${w.parallel ? '<span class="pill">parallel view</span>' : ''}</h4>
      <div class="meta">${esc(w.author || '—')} · work ${w.id} · ${w.n} published version${w.n > 1 ? 's' : ''}</div>
      ${w.titles.map(t => `
        <div class="t">
          <span class="c">${t.have ? '<strong>' + t.code + '</strong>' : t.code}</span>
          <span class="lang">${t.lang || '??'}</span>
          <span class="tt">${esc(t.title)}${t.credit ? ` <span class="au">— ${esc(t.credit)}</span>` : ''}</span>
          ${t.db ? '<span class="pill db">in DB</span>' : t.have ? '<span class="pill have">TEI on disk</span>' : ''}
          ${t.meta ? '<span class="pill">has metadata</span>' : ''}
        </div>`).join('')}
    </div>`).join('');
  document.getElementById('wmore').textContent = list.length > shown.length
    ? `Showing the first ${shown.length}. Narrow the search to see the rest.` : '';
}
renderWorks();

document.querySelectorAll('.tabs button').forEach(b => b.onclick = () => {
  document.querySelectorAll('.tabs button').forEach(x => x.setAttribute('aria-selected', x === b));
  document.querySelectorAll('.panel').forEach(p => p.hidden = p.id !== 'panel-' + b.dataset.tab);
});
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
