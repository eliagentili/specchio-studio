#!/usr/bin/env python3
"""Build the dependency-free bilingual marketing preview. Never copies app sources."""
from pathlib import Path
from html import escape
import json
import shutil

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'docs'
BASE = 'https://eliagentili.github.io/specchio-studio-site/'
PROFILE = 'https://github.com/eliagentili'
REPO = PROFILE + '/specchio-studio-site'
COPY = {
'en': {
 'title': 'Specchio Studio — Your device. Ready to share.',
 'description': 'A native Mac workflow by Elia Gentili for iPhone and iPad demos, annotated bug reports and creator exports. Preview of a free release in preparation.',
 'nav': ['Workflow', 'Made by Elia', 'Questions'], 'skip':'Skip to content', 'other':'Italiano',
 'badge':'A native Mac app · Free release in preparation',
 'headline':'Your device.<br><em>Ready to share.</em>',
 'intro':'Turn iPhone and iPad captures into product demos, creator assets and clearer bug reports. All on your Mac.',
 'cta':'See what you can make', 'authorlink':'Meet the maker',
 'requirements':'macOS 14+ · Apple Silicon · Local processing',
 'imagealt':'Actual app-generated demo composition: MAKE ROOM artwork in a generic device frame on a green and navy background.',
 'caption':'Rendered by the real app canvas. Demo artwork, not a connected device or a full app screenshot.',
 'stage_label':'A little more than a recording.', 'stage_bottom':'Capture → Compose → Share',
 'bridge':'A screen capture is just the beginning.',
 'bridge_body':'Give your work the context it deserves. Frame a demo, explain a problem, or prepare the same idea for three different places.',
 'workflow_label':'Three ways to put it to work', 'workflow_title':'From “look at this”<br>to <em>“here it is.”</em>',
 'tabs':['Product demos','Bug reports','Creator exports'],
 'panels':[
 ['Give your next demo a proper stage.', 'Capture an iPhone or iPad through USB or the wireless receiver, or choose a Mac window or screen. Record first, then compose the result.', ['Record the original in H.264 or HEVC MOV','Add a background, frame and time trim on export','Keep source audio when available'], 'Original recordings and composed exports are separate steps.'],
 ['Make the problem easier to understand.', 'Put steps, expected behavior and the actual result beside an annotated screenshot. Export one folder with Markdown, JSON and image attachments.', ['Annotate and extract text with local OCR','Draw opaque masks or review OCR suggestions','Unmasked originals are excluded by default'], 'Review report text and attachments before sharing. Detection can miss sensitive details.'],
 ['One composition. More places to share it.', 'Prepare portrait, square and landscape assets together, with a cover and a file manifest. Save a style to make the next export feel consistent.', ['9:16, 1:1 and 16:9 image or video packages','A cover with an optional title','Reusable backgrounds, framing and orientation'], 'Video presets: 1080 × 1920, 1080 × 1080 and 1920 × 1080.']
 ],
 'formats_label':'Made for the places you publish', 'formats_title':'One idea.<br><em>Three proportions.</em>',
 'formats_body':'The same app-generated artwork, composed in three actual canvas exports. The source stays fully in frame.',
 'formats_alt':'Three real app canvas renders of the same demo in portrait 9:16, square 1:1 and landscape 16:9.',
 'formats_caption':'Actual canvas renders shown at reduced resolution. These examples use the default fit setting to keep the whole source visible.',
 'privacy_label':'Share the work. Check the details.', 'privacy_title':'Some things<br><em>should stay yours.</em>',
 'privacy_body':'Mask sensitive regions before export. The app draws opaque areas into exported image pixels; local OCR can suggest details to review.',
 'privacy_try':'Try this illustration', 'privacy_toggle':'Show example data', 'privacy_hidden':'Hide example data',
 'privacy_note':'Illustration with fictional data. In the app, video masks are fixed areas throughout a clip; they do not follow moving content. Originals, audio and manually written report fields are not automatically redacted.',
 'sample_title':'Demo account', 'sample_name':'Alex Example', 'sample_label':'Email address', 'masked':'Masked in this illustration',
 'maker_label':'Designed and built by Elia Gentili', 'maker_title':'An idea, carried<br><em>through to the details.</em>',
 'maker_body':'Specchio Studio is my exploration of a complete Mac workflow: from device capture and native media processing to thoughtful exports and the small details that make an app useful.',
 'maker_stack':'Built with SwiftUI, AppKit, AVFoundation, VideoToolbox and Vision. Designed for local processing, with no app account required.',
 'maker_cta':'Explore my work on GitHub',
 'faq_label':'Before you ask', 'faq_title':'The useful details.',
 'faqs':[
 ['Can I download it now?', 'This is a preview. A free release is being prepared; there is no public app download yet. Release review and further physical-device testing are still in progress.'],
 ['Which systems does it support?', 'The current target is macOS 14 or later on Apple Silicon. The app captures iPhone, iPad and Mac sources. There are no Windows or Linux versions. The current app interface is in Italian.'],
 ['Does my content go to a cloud service?', 'Capture, OCR and composition run locally on your Mac, without an app account. This website has no analytics, advertising, remote fonts or third-party embeds. GitHub hosts it and handles ordinary request data.'],
 ['Can I edit the recording as I capture?', 'The app records the source first. You then open the video composition tool to add framing, backgrounds, trim and fixed privacy masks. Composed video exports use H.264.'],
 ['What is still being checked?', 'More tests with physical devices, long sessions and first launch on another Mac are pending. The current local build is not notarized. Code and asset provenance, name availability and distribution rights also need review before an app release.'],
 ['How can I share feedback?', 'Use the public website repository for suggestions about the project and its presentation. Do not include personal data or private recordings in a public issue.']
 ],
 'closing_title':'Good work deserves<br><em>a clear presentation.</em>',
 'closing_body':'Follow the project, explore the work behind it, or tell me where this workflow would help you.',
 'closing_cta':'Join the conversation on GitHub',
 'status':'Project preview · Free release in preparation',
 'footer':['Website source','Privacy','Made by Elia Gentili'],
 'privacy_page_title':'Privacy, simply.',
 'privacy_page_body':'This static website does not use analytics, advertising, tracking cookies, third-party embeds or remotely loaded fonts. All website assets are served from the same GitHub Pages site. Interactive examples run in your browser and do not send their state to a server.',
 'privacy_host':'GitHub Pages hosts this site. GitHub may process request information, such as IP addresses and browser details, under its own privacy statement. Opening a GitHub link takes you to a separate service with its own policies.',
 'privacy_app':'The app preview describes local capture, OCR and composition. This page does not distribute the app, collect recordings, offer accounts or accept payments.',
 'back':'Back to Specchio Studio', 'host_policy':'GitHub privacy statement',
 'notfound':'This page is out of frame.', 'notfound_body':'The link may have changed. Head back to the project preview.'
},
'it': {
 'title':'Specchio Studio — Il tuo dispositivo. Pronto da condividere.',
 'description':'Un’app Mac di Elia Gentili per demo di iPhone e iPad, segnalazioni bug annotate e pacchetti creator. Anteprima di un rilascio gratuito in preparazione.',
 'nav':['Come funziona','Chi c’è dietro','Domande'], 'skip':'Vai al contenuto', 'other':'English',
 'badge':'Un’app nativa per Mac · Rilascio gratuito in preparazione',
 'headline':'Il tuo dispositivo.<br><em>Pronto da condividere.</em>',
 'intro':'Trasforma le acquisizioni di iPhone e iPad in demo di prodotto, contenuti e segnalazioni bug più chiare. Tutto sul tuo Mac.',
 'cta':'Scopri cosa puoi creare','authorlink':'Conosci Elia',
 'requirements':'macOS 14+ · Apple Silicon · Elaborazione locale',
 'imagealt':'Composizione demo generata dall’app: grafica MAKE ROOM in una cornice generica su uno sfondo verde e blu.',
 'caption':'Render del vero canvas dell’app. Grafica dimostrativa, non un dispositivo collegato o uno screenshot dell’interfaccia completa.',
 'stage_label':'Qualcosa in più di una registrazione.', 'stage_bottom':'Acquisisci → Componi → Condividi',
 'bridge':'Acquisire lo schermo è solo l’inizio.',
 'bridge_body':'Dai al tuo lavoro il contesto che merita. Incornicia una demo, spiega un problema o prepara la stessa idea per tre destinazioni diverse.',
 'workflow_label':'Tre modi per usarla', 'workflow_title':'Da “guarda qui”<br>a <em>“ecco tutto.”</em>',
 'tabs':['Demo di prodotto','Segnalazioni bug','Pacchetti creator'],
 'panels':[
 ['Dai alla prossima demo lo spazio che merita.', 'Acquisisci iPhone o iPad via USB o con il ricevitore wireless, oppure scegli una finestra o uno schermo del Mac. Prima registri, poi componi il risultato.', ['Registra l’originale in MOV H.264 o HEVC','Aggiungi sfondo, cornice e taglio temporale in esportazione','Mantieni l’audio della sorgente quando disponibile'], 'Registrazione originale ed esportazione composta sono due passaggi distinti.'],
 ['Rendi il problema più facile da capire.', 'Affianca passaggi, risultato atteso e comportamento osservato a uno screenshot annotato. Esporta una cartella con Markdown, JSON e immagini allegate.', ['Annota ed estrai testo con OCR locale','Disegna maschere opache o verifica i suggerimenti OCR','Gli originali non oscurati sono esclusi per impostazione iniziale'], 'Controlla testo e allegati prima di condividerli. Il rilevamento può non individuare tutti i dati sensibili.'],
 ['Una composizione. Più posti in cui condividerla.', 'Prepara insieme contenuti verticali, quadrati e orizzontali, con copertina e riepilogo dei file. Salva uno stile per dare continuità alle esportazioni successive.', ['Pacchetti di immagini o video in 9:16, 1:1 e 16:9','Una copertina con titolo facoltativo','Sfondi, cornici e orientamento riutilizzabili'], 'Preset video: 1080 × 1920, 1080 × 1080 e 1920 × 1080.']
 ],
 'formats_label':'Per i posti in cui pubblichi', 'formats_title':'Una sola idea.<br><em>Tre proporzioni.</em>',
 'formats_body':'La stessa grafica dimostrativa, composta in tre esportazioni reali del canvas. La sorgente resta interamente visibile.',
 'formats_alt':'Tre render reali del canvas della stessa demo nei formati verticale 9:16, quadrato 1:1 e orizzontale 16:9.',
 'formats_caption':'Render reali del canvas a risoluzione ridotta. Questi esempi usano lo zoom Adatta per mantenere visibile l’intera sorgente.',
 'privacy_label':'Condividi il lavoro. Controlla i dettagli.', 'privacy_title':'Alcune cose<br><em>restano tue.</em>',
 'privacy_body':'Oscura le aree sensibili prima dell’esportazione. L’app applica rettangoli opachi ai pixel delle immagini esportate; l’OCR locale può suggerire dettagli da verificare.',
 'privacy_try':'Prova questa illustrazione', 'privacy_toggle':'Mostra i dati di esempio','privacy_hidden':'Nascondi i dati di esempio',
 'privacy_note':'Illustrazione con dati fittizi. Nell’app le maschere video sono fisse per tutta la clip e non seguono contenuti in movimento. Originali, audio e campi scritti nel report non vengono oscurati automaticamente.',
 'sample_title':'Account demo', 'sample_name':'Alex Example','sample_label':'Indirizzo email','masked':'Oscurato in questa illustrazione',
 'maker_label':'Progettata e sviluppata da Elia Gentili', 'maker_title':'Un’idea, seguita<br><em>fino ai dettagli.</em>',
 'maker_body':'Specchio Studio è la mia esplorazione di un flusso completo su Mac: dall’acquisizione dei dispositivi all’elaborazione multimediale nativa, fino alle esportazioni e ai piccoli dettagli che rendono utile un’app.',
 'maker_stack':'Sviluppata con SwiftUI, AppKit, AVFoundation, VideoToolbox e Vision. Pensata per l’elaborazione locale, senza account nell’app.',
 'maker_cta':'Esplora il mio lavoro su GitHub',
 'faq_label':'Prima di chiedertelo','faq_title':'I dettagli utili.',
 'faqs':[
 ['Posso già scaricarla?', 'Questa è un’anteprima. È in preparazione un rilascio gratuito; il download pubblico dell’app non è ancora disponibile. Sono in corso la revisione del rilascio e altre prove su dispositivi fisici.'],
 ['Su quali sistemi funziona?', 'Il target attuale è macOS 14 o successivo su Apple Silicon. L’app acquisisce sorgenti iPhone, iPad e Mac. Non ci sono versioni per Windows o Linux. L’interfaccia attuale dell’app è in italiano.'],
 ['I miei contenuti vengono inviati a un servizio cloud?', 'Acquisizione, OCR e composizione avvengono localmente sul Mac, senza account nell’app. Questo sito non ha analytics, pubblicità, font remoti o contenuti incorporati di terzi. GitHub lo ospita e gestisce i normali dati delle richieste.'],
 ['Posso comporre il video mentre registro?', 'L’app registra prima la sorgente. Poi apri lo strumento di composizione video per aggiungere cornici, sfondi, taglio e maschere privacy fisse. I video composti vengono esportati in H.264.'],
 ['Cosa manca ancora da verificare?', 'Restano altre prove con dispositivi fisici, sessioni lunghe e primo avvio su un altro Mac. La build locale attuale non è notarizzata. Prima del rilascio dell’app vanno inoltre completate le verifiche su provenienza di codice e risorse, disponibilità del nome e diritti di distribuzione.'],
 ['Come posso lasciare un suggerimento?', 'Usa il repository pubblico del sito per suggerimenti sul progetto e sulla sua presentazione. Non inserire dati personali o registrazioni private in una issue pubblica.']
 ],
 'closing_title':'Un buon lavoro merita<br><em>di essere raccontato bene.</em>',
 'closing_body':'Segui il progetto, esplora il lavoro che c’è dietro o raccontami dove questo flusso ti sarebbe utile.',
 'closing_cta':'Parliamone su GitHub', 'status':'Anteprima del progetto · Rilascio gratuito in preparazione',
 'footer':['Sorgenti del sito','Privacy','Creato da Elia Gentili'],
 'privacy_page_title':'Privacy, con semplicità.',
 'privacy_page_body':'Questo sito statico non utilizza analytics, pubblicità, cookie di tracciamento, contenuti incorporati di terzi o font caricati da servizi esterni. Tutte le risorse provengono dallo stesso sito GitHub Pages. Gli esempi interattivi funzionano nel browser e non inviano il loro stato a un server.',
 'privacy_host':'Il sito è ospitato da GitHub Pages. GitHub può elaborare informazioni delle richieste, come indirizzi IP e dettagli del browser, secondo la propria informativa. Aprendo un link GitHub accedi a un servizio separato con le proprie regole.',
 'privacy_app':'L’anteprima dell’app descrive acquisizione, OCR e composizione locali. Questa pagina non distribuisce l’app, non raccoglie registrazioni, non offre account e non accetta pagamenti.',
 'back':'Torna a Specchio Studio','host_policy':'Informativa privacy di GitHub',
 'notfound':'Questa pagina è fuori inquadratura.', 'notfound_body':'Il collegamento potrebbe essere cambiato. Torna all’anteprima del progetto.'
}}

def head(lang, c, page=''):
    prefix = '../' if lang == 'it' else ''
    path = ('it/' if lang == 'it' else '') + page
    title = c['title'] if not page else c['privacy_page_title'] + ' — Specchio Studio'
    schema = {'@context':'https://schema.org','@type':'WebSite','name':'Specchio Studio','url':BASE,'inLanguage':['en','it'],'description':c['description'],'author':{'@type':'Person','name':'Elia Gentili','url':PROFILE}}
    return f'''<!doctype html>
<html lang="{lang}" class="no-js"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title><meta name="description" content="{escape(c['description'])}">
<meta name="theme-color" content="#f6f5ef"><meta name="color-scheme" content="light">
<link rel="canonical" href="{BASE}{path}"><link rel="alternate" hreflang="en" href="{BASE}{page}"><link rel="alternate" hreflang="it" href="{BASE}it/{page}"><link rel="alternate" hreflang="x-default" href="{BASE}{page}">
<meta property="og:type" content="website"><meta property="og:title" content="{escape(title)}"><meta property="og:description" content="{escape(c['description'])}"><meta property="og:url" content="{BASE}{path}"><meta property="og:site_name" content="Specchio Studio"><meta property="og:locale" content="{'it_IT' if lang == 'it' else 'en_US'}"><meta property="og:image" content="{BASE}assets/social-card{'-it' if lang == 'it' else ''}.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630"><meta property="og:image:alt" content="Specchio Studio — Elia Gentili">
<meta name="twitter:image:alt" content="Specchio Studio — Elia Gentili"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{escape(title)}"><meta name="twitter:description" content="{escape(c['description'])}"><meta name="twitter:image" content="{BASE}assets/social-card{'-it' if lang == 'it' else ''}.png">
<link rel="icon" href="{prefix}assets/favicon.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="{prefix}assets/app-icon.png"><link rel="stylesheet" href="{prefix}styles.css"><script src="{prefix}site.js" defer></script><script type="application/ld+json">{json.dumps(schema, ensure_ascii=False)}</script></head>'''

def footer(lang,c):
    return f'''<footer class="shell footer"><a class="wordmark" href="./">Specchio Studio<span class="footer-by">Elia Gentili · 2026</span></a><div><a href="{REPO}">{c['footer'][0]} ↗</a><a href="privacy.html">{c['footer'][1]}</a><a href="{PROFILE}">{c['footer'][2]} ↗</a></div></footer>'''

def build(lang,c):
    prefix = '../' if lang == 'it' else ''
    altlang = '../' if lang == 'it' else 'it/'
    tabs=''.join(f'<button id="tab-{i}" class="workflow-tab" role="tab" aria-selected="{str(i==0).lower()}" aria-controls="panel-{i}" tabindex="{0 if i==0 else -1}" type="button"><span>0{i+1}</span>{v}<span class="tab-arrow" aria-hidden="true">↗</span></button>' for i,v in enumerate(c['tabs']))
    panels=''.join(f'<section id="panel-{i}" class="workflow-panel" role="tabpanel" aria-labelledby="tab-{i}" tabindex="0" {"hidden" if i else ""}><span class="panel-number" aria-hidden="true">0{i+1}</span><h3>{p[0]}</h3><p>{p[1]}</p><ul>'+''.join(f'<li>{s}</li>' for s in p[2])+f'</ul><p class="fine">{p[3]}</p></section>' for i,p in enumerate(c['panels']))
    faqs=''.join(f'<details><summary>{q}<span aria-hidden="true">+</span></summary><p>{a}</p></details>' for q,a in c['faqs'])
    content=head(lang,c)+f'''<body><a class="skip" href="#main">{c['skip']}</a>
<header class="shell header"><a class="brand" href="./" aria-label="Specchio Studio"><img src="{prefix}assets/app-icon.png" width="38" height="38" alt=""><span>Specchio Studio</span></a><nav aria-label="{'Navigazione principale' if lang=='it' else 'Main navigation'}"><a href="#workflow">{c['nav'][0]}</a><a href="#maker">{c['nav'][1]}</a><a href="#questions">{c['nav'][2]}</a><a class="language" href="{altlang}" lang="{'en' if lang=='it' else 'it'}" hreflang="{'en' if lang=='it' else 'it'}">{c['other']} <span aria-hidden="true">↗</span></a></nav></header>
<main id="main">
<section class="shell hero"><div class="hero-copy"><p class="eyebrow status"><span></span>{c['badge']}</p><h1>{c['headline']}</h1><p class="hero-intro">{c['intro']}</p><div class="actions"><a class="button" href="#workflow">{c['cta']} <span aria-hidden="true">↗</span></a><a class="text-link" href="#maker">{c['authorlink']} <span aria-hidden="true">→</span></a></div><p class="requirements">{c['requirements']}</p></div><figure class="hero-figure"><div class="stage"><p class="stage-label">{c['stage_label']}</p><div class="stage-orbit" aria-hidden="true"></div><img class="hero-art" src="{prefix}assets/demo-preview.webp" width="1000" height="1200" alt="{c['imagealt']}" fetchpriority="high"><div class="stage-bottom"><span class="stage-dot"></span>{c['stage_bottom']}<span aria-hidden="true">↗</span></div></div><figcaption>{c['caption']}</figcaption></figure></section>
<div class="shell bridge"><span class="asterisk" aria-hidden="true">✳</span><h2>{c['bridge']}</h2><p>{c['bridge_body']}</p></div>
<section class="workflow-wrap" id="workflow"><div class="shell"><p class="eyebrow">{c['workflow_label']}</p><h2 class="section-title">{c['workflow_title']}</h2><div class="workflow"><div class="workflow-tabs" role="tablist" aria-label="{'Flussi di lavoro' if lang=='it' else 'Workflows'}">{tabs}</div><div class="workflow-panels">{panels}</div></div></div></section>
<section class="shell formats"><div class="split-heading"><div><p class="eyebrow">{c['formats_label']}</p><h2 class="section-title">{c['formats_title']}</h2></div><p>{c['formats_body']}</p></div><figure><img src="{prefix}assets/formats-proof.webp" width="1440" height="840" alt="{c['formats_alt']}" loading="lazy"><figcaption>{c['formats_caption']}</figcaption></figure></section>
<section class="privacy-wrap"><div class="shell privacy-grid"><div><p class="eyebrow">{c['privacy_label']}</p><h2 class="section-title">{c['privacy_title']}</h2><p class="section-body">{c['privacy_body']}</p><p class="fine">{c['privacy_note']}</p></div><div class="privacy-example"><p class="eyebrow">{c['privacy_try']}</p><div class="sample-card"><div class="sample-bar"><span></span><span></span><span></span><span class="sample-title">{c['sample_title']}</span></div><div class="sample-content"><span class="avatar" aria-hidden="true">A</span><h3>{c['sample_name']}</h3><p>{c['sample_label']}</p><div class="sample-value" aria-live="polite"><span class="mask-placeholder">{c['masked']}</span><span class="example-email" hidden>demo@example.invalid</span></div></div></div><button class="mask-toggle" type="button" aria-pressed="false" data-show="{c['privacy_toggle']}" data-hide="{c['privacy_hidden']}">{c['privacy_toggle']} <span aria-hidden="true">↗</span></button></div></div></section>
<section class="shell maker" id="maker"><div class="maker-mark" aria-hidden="true"><div class="mirror-one"></div><div class="mirror-two"></div><span>EG<span>↗</span></span></div><div><p class="eyebrow">{c['maker_label']}</p><h2 class="section-title">{c['maker_title']}</h2><p class="section-body">{c['maker_body']}</p><p class="maker-stack">{c['maker_stack']}</p><a class="text-link" href="{PROFILE}">{c['maker_cta']} ↗</a></div></section>
<section class="shell questions" id="questions"><div><p class="eyebrow">{c['faq_label']}</p><h2 class="section-title">{c['faq_title']}</h2></div><div class="faq-list">{faqs}</div></section>
<section class="closing"><div class="shell"><p class="eyebrow">Specchio Studio × Elia Gentili</p><h2 class="section-title">{c['closing_title']}</h2><p>{c['closing_body']}</p><a class="button light" href="{REPO}/issues">{c['closing_cta']} ↗</a><p class="closing-status"><span></span>{c['status']}</p></div></section></main>{footer(lang,c)}</body></html>'''
    directory = DEST / ('it' if lang=='it' else '')
    directory.mkdir(parents=True,exist_ok=True)
    (directory/'index.html').write_text(content,encoding='utf-8')
    privacy=head(lang,c,'privacy.html')+f'<body><header class="shell header"><a class="brand" href="./">Specchio Studio</a><a href="{altlang}privacy.html">{c["other"]} ↗</a></header><main class="shell prose" id="main"><p class="eyebrow">Specchio Studio</p><h1>{c["privacy_page_title"]}</h1><p>{c["privacy_page_body"]}</p><p>{c["privacy_host"]}</p><p><a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">{c["host_policy"]} ↗</a></p><p>{c["privacy_app"]}</p><a class="button" href="./">{c["back"]} →</a></main>{footer(lang,c)}</body></html>'
    (directory/'privacy.html').write_text(privacy,encoding='utf-8')

for language,copy in COPY.items():
    build(language,copy)
(DEST/'.nojekyll').touch()
shutil.copyfile(ROOT/'LICENSE', DEST/'LICENSE')
(DEST/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join(f'<url><loc>{BASE}{p}</loc></url>' for p in ('','it/','privacy.html','it/privacy.html'))+'</urlset>\n',encoding='utf-8')
(DEST/'404.html').write_text('''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Page not found — Specchio Studio</title><link rel="stylesheet" href="'''+BASE+'''styles.css"></head><body><main class="shell prose"><p class="eyebrow">Specchio Studio · 404</p><h1>This page is out of frame.</h1><p>The link may have changed. Head back to the project preview.</p><a class="button" href="'''+BASE+'''">Back to Specchio Studio →</a></main></body></html>''',encoding='utf-8')
print('Built English and Italian preview pages in docs/. No app files copied.')
