import os, html
from rig import rig, axo

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), '4-handoff.html')

def rd(n):
    return open(os.path.join(HERE, n)).read()

mascots = {k: rd(f) for k, f in [('wait', 'waiting-on-you.b64'), ('ready', 'ready.b64'), ('sleep', 'sleeping.b64'), ('happy', 'happy.b64')]}
mcss = '\n'.join('.mi-%s { background-image: url("data:image/png;base64,%s"); }' % (k, v) for k, v in mascots.items())

css = rd('style.css') + '\n' + mcss + '\n'
js = rd('app.js')

EXT = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><path d="M6 3h7v7M13 3 5 11"/></svg>'
GH = '<svg viewBox="0 0 16 16" aria-hidden="true" fill="currentColor"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>'
SUN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>'
REPO = 'https://github.com/Lawliang/lostty'

SKINS = [
    ('The arcade pack', [
        ('neon-arcade', 'legendary', 'sk-neon', 'tx-grid', 'Bright magenta and cyan on a dark purple.'),
        ('sunset-drive', 'epic', 'sk-sunset', 'tx-scan', 'Warm orange and pink on a dark plum with scanlines.'),
        ('mint-protocol', 'rare', 'sk-mint', 'tx-dots', 'Neon green and yellow on a dark teal.'),
        ('deep-dive', 'rare', 'sk-deep', 'tx-bubbles', 'Bright cyan and purple on a dark blue.'),
        ('lava-rush', 'epic', 'sk-lava', 'tx-diag', 'Warm orange and yellow on a dark brown with diagonal texture.'),
        ('bubble-pop', 'common', 'sk-bubble', 'tx-sparkle', 'Hot pink and yellow on a purple with sparkle texture.'),
    ]),
    ('The Olympian boon pack', [
        ('thunderhead', 'epic, Zeus', 'sk-thunder', 'tx-bolt', 'Thunder gold on storm navy with lightning.'),
        ('undertow', 'rare, Poseidon', 'sk-undertow', 'tx-tide', 'Sea-foam on abyssal teal with tide lines.'),
        ('bloodrite', 'heroic, Ares', 'sk-blood', 'tx-blade', 'Battle red on dried blood with blade marks.'),
        ('heartsease', 'common, Aphrodite', 'sk-hearts', 'tx-petal', 'Rose pink on dusk rose with petals.'),
        ('silverbow', 'legendary, Artemis', 'sk-silver', 'tx-stars', 'Hunter green on night forest with a starfield.'),
        ('stormsurge', 'duo, Zeus & Poseidon', 'sk-storm', 'tx-surge', 'Gold lightning over teal swells.'),
    ]),
]
PATHS = {'neon-arcade': 'lostty/skins', 'sunset-drive': 'lostty/stay-awake', 'mint-protocol': 'api-server/main', 'deep-dive': 'home',
         'lava-rush': 'lostty/website', 'bubble-pop': 'lostty/website', 'thunderhead': 'lostty/main', 'undertow': 'tide/main',
         'bloodrite': 'ares/main', 'heartsease': 'notes', 'silverbow': 'api-server/main', 'stormsurge': 'lostty/skins'}

picker = []
for grp, items in SKINS:
    picker.append('<div class="pk-group">%s</div>' % grp)
    for (sid, rar, sk, tx, desc) in items:
        rarc = rar.split(',')[0]
        picker.append(
            '<button type="button" id="pk-%s" class="pk %s" aria-pressed="%s" data-id="%s" data-sk="%s" data-tx="%s" data-rar="%s" data-rarc="%s" data-desc="%s" data-path="%s">'
            '<span class="sws %s" aria-hidden="true"></span><span class="n">%s</span><span class="r">%s</span></button>'
            % (sid, sk, 'true' if sid == 'neon-arcade' else 'false', sid, sk, tx, html.escape(rar), rarc, html.escape(desc), PATHS[sid], tx, sid, html.escape(rar)))
picker = '\n'.join(picker)

hero_rig = rig('stop rise wave', '', 'A Mac window running four Claude sessions, and an iPhone listing them. One session has stopped on a permission prompt; on the phone it rises to the top as Waiting on you.')
stage_rig = rig('', '', 'The Mac and the iPhone acting out each fix as you scroll.')
fig1 = rig('stop rise wave', 'solo-phone', 'The phone list with the waiting session sorted first and the mascot waving.')
fig2 = rig('rise term snap answered', 'solo-phone', 'The phone showing the real terminal; a tap between the 1 and 2 keys types 1.')
fig3 = rig('rise answered s1 s2 s3 s4 trace', 'solo-mac', 'The Mac window with four panes, each in its own skin, and a glow tracing the window.')
fig4 = rig('rise answered spawn s1 s2 s3 s4', '', 'A new session started from the phone, open on the Mac and the phone at once.')

PAGE = open(os.path.join(HERE, 'page.html')).read()
for k, v in {
    '%%CSS%%': css, '%%JS%%': js, '%%LOGO%%': axo(blink=True), '%%LOGO2%%': axo(), '%%EXT%%': EXT, '%%GH%%': GH, '%%SUN%%': SUN,
    '%%REPO%%': REPO, '%%HERO_RIG%%': hero_rig, '%%STAGE_RIG%%': stage_rig, '%%FIG1%%': fig1, '%%FIG2%%': fig2, '%%FIG3%%': fig3,
    '%%FIG4%%': fig4, '%%PICKER%%': picker,
}.items():
    PAGE = PAGE.replace(k, v)
assert '%%' not in PAGE, PAGE[PAGE.index('%%') - 40:PAGE.index('%%') + 40]
open(OUT, 'w').write(PAGE)
print(OUT, len(PAGE))
