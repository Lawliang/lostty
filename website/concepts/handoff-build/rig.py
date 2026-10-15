AXO = ('<svg viewBox="0 0 100 100" aria-hidden="true" class="axo">'
       '<path d="M60 82 C70 86 80 84 84 76 C86 72 82 70 80 73 C77 78 70 79 63 76 Z" fill="#EC97C6"/>'
       '<ellipse cx="50" cy="76" rx="15" ry="12" fill="#EC97C6"/><ellipse cx="50" cy="79" rx="8" ry="6" fill="#F7B2D8"/>'
       '<ellipse cx="39" cy="80" rx="4.2" ry="3.2" fill="#F7B2D8"/><ellipse cx="61" cy="80" rx="4.2" ry="3.2" fill="#F7B2D8"/>'
       '<ellipse cx="43" cy="88" rx="5" ry="3" fill="#F7B2D8"/><ellipse cx="57" cy="88" rx="5" ry="3" fill="#F7B2D8"/>'
       '<ellipse cx="14" cy="21" rx="9" ry="4.6" transform="rotate(-42 14 21)" fill="#E5199C"/>'
       '<ellipse cx="86" cy="21" rx="9" ry="4.6" transform="rotate(42 86 21)" fill="#E5199C"/>'
       '<ellipse cx="9" cy="34" rx="9" ry="4.6" transform="rotate(-12 9 34)" fill="#E5199C"/>'
       '<ellipse cx="91" cy="34" rx="9" ry="4.6" transform="rotate(12 91 34)" fill="#E5199C"/>'
       '<ellipse cx="11" cy="47" rx="8.5" ry="4.3" transform="rotate(18 11 47)" fill="#E5199C"/>'
       '<ellipse cx="89" cy="47" rx="8.5" ry="4.3" transform="rotate(-18 89 47)" fill="#E5199C"/>'
       '<path d="M50 15 C76.4 15 83 26.7 83 42.3 C83 60.5 69.8 67 50 67 C30.2 67 17 60.5 17 42.3 C17 26.7 23.6 15 50 15 Z" fill="#F7B2D8"/>'
       '<ellipse cx="34" cy="24" rx="7" ry="3.2" fill="#FFFFFF" opacity="0.35" transform="rotate(-18 34 24)"/>'
       '<path d="M33 36 L42 43 L33 50" fill="none" stroke="#3A1530" stroke-width="4.4" stroke-linecap="round" stroke-linejoin="round"/>'
       '<path class="BLINK" d="M56 43 H68" stroke="#3A1530" stroke-width="4.4" stroke-linecap="round"/>'
       '<path d="M46 53 Q48 56 50 53.5 Q52 56 54 53" fill="none" stroke="#3A1530" stroke-width="2.42" stroke-linecap="round" stroke-linejoin="round"/>'
       '<ellipse cx="26" cy="55" rx="5" ry="3" fill="#E5199C" opacity="0.45"/><ellipse cx="75" cy="55" rx="5" ry="3" fill="#E5199C" opacity="0.45"/></svg>')

def axo(blink=False, cls=''):
    s = AXO.replace('class="BLINK"', 'class="blink"' if blink else '')
    if cls:
        s = s.replace('class="axo"', 'class="axo %s"' % cls)
    return s

BELL = '<svg viewBox="0 0 24 24" fill="none" stroke="#F3F0F6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>'
PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="#F3F0F6" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>'
SEARCH = '<svg viewBox="0 0 24 24" fill="none" stroke="#8E8897" stroke-width="2.4" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>'


def pane(key, skin, tex, head, status, body):
    return ('<div class="pane p-%s %s"><div class="skin %s"></div>'
            '<div class="ph"><span class="pp"><b>&gt;</b> %s</span><span class="pst">%s</span></div>'
            '%s</div>') % (key, skin, tex, head, status, body)


def card(key, title, path, detail, status, mimg, extra=''):
    return ('<div class="card c-%s %s"><div class="c-body">'
            '<div class="c-t"><i class="sw"></i>%s</div>'
            '<div class="c-p"><b>&gt;</b> %s</div>'
            '<div class="c-d-line">%s</div>'
            '<div class="c-s">%s</div></div>%s<span class="chev">&#8250;</span></div>') % (key, extra, title, path, detail, status, mimg)


def rig(flags='', mode='', label=''):
    pa = pane('a', 'sk-neon', 'tx-grid', 'lostty/skins',
              '<span class="st-base"><span class="star">&#10035;</span> Editing App.swift</span>'
              '<span class="st-stop">Waiting on you</span><span class="st-ans"><span class="star">&#10035;</span> Running tests</span>',
              '<pre class="pt st-base"><span class="a">&gt;</span> make the skin picker remember\n  the last pane\n<span class="b">&#9210;</span> Read(SkinPicker.swift)\n<span class="b">&#9210;</span> Update(App.swift) <span class="m">+18 &#8722;4</span>\n<span class="a">&#10035;</span> Working&#8230; <span class="m">(1m 12s)</span></pre>'
              '<pre class="pt st-stop"><span class="b">&#9210;</span> Bash(xcodebuild test\n    -scheme LosttyRemote)\n<span class="q">Do you want to proceed?\n<span class="a">&#10095; 1. Yes</span>\n  2. Yes, and don&#8217;t ask again\n  3. No</span></pre>'
              '<pre class="pt st-ans"><span class="b">&#9210;</span> Bash(xcodebuild test\n    -scheme LosttyRemote)\n  <span class="a">&#10095; 1. Yes</span> <span class="m">from iPhone</span>\n<span class="a">&#10035;</span> Running tests&#8230; <span class="m">128 passed</span></pre>'
              '<span class="same">Same session as the phone</span>')
    pb = pane('b', 'sk-sunset', 'tx-scan', 'lostty/stay-awake',
              '<span class="star">&#10035;</span> Editing StayAwakeController.swift',
              '<pre class="pt"><span class="a">&gt;</span> fix the login bug\n<span class="b">&#9210;</span> Read(LoginView.swift)\n<span class="b">&#9210;</span> Update(StayAwakeController.swift)\n<span class="a">&#10035;</span> Incubating&#8230; <span class="m">(3m 52s)</span></pre>')
    pc = pane('c', 'sk-deep', 'tx-bubbles', 'home', 'Ready',
              '<pre class="pt"><span class="a">$</span> tail -f deploy.log\n<span class="b">&#10003;</span> build 4312 healthy\n<span class="b">&#10003;</span> watch ready\n<span class="a">$</span> </pre>')
    pd = pane('d', 'sk-silver', 'tx-stars', 'api-server/main', 'Idle &middot; 2h',
              '<pre class="pt"><span class="a">$</span> npm run dev\n<span class="m">listening on :8080</span>\n<span class="m">^C</span>\n<span class="a">$</span> </pre>')
    pe = pane('e', 'sk-bubble', 'tx-sparkle', 'lostty/website', 'Started from iPhone',
              '<pre class="pt"><span class="a">&#10043;</span> Welcome to Claude Code\n  <span class="m">cwd</span> ~/code/lostty/website\n  <span class="m">model</span> Opus\n\n<span class="a">&gt;</span> <span class="caret"></span></pre>')

    mac = ('<div class="mac"><div class="mac-bar"><span class="lights"><i></i><i></i><i></i></span>'
           '<span class="mac-title">Lostty</span><span class="pill"><b>&gt;</b> lostty/skins</span></div>'
           '<div class="mac-body"><div class="col">%s%s</div><div class="col">%s%s</div><div class="col col-e">%s</div></div>'
           '<div class="mac-usage"><span>Opus</span><span>ctx <span class="meter">&#9632;&#9632;&#9632;&#9633;&#9633;</span> 50K</span><span>5h <span class="meter">&#9632;&#9633;&#9633;&#9633;&#9633;</span> 22%%</span></div></div>') % (pa, pb, pc, pd, pe)

    cards = (
        card('e', 'Website copy pass', 'lostty/website', 'Starting Claude &middot; Opus', '<span>&#10035; Starting&#8230;</span>', '<span class="c-m base mi-happy"></span>', 'sk-bubble') +
        card('a', 'Lostty UI redesign plan', 'lostty/skins',
             '<span class="v-base">Editing App.swift</span><span class="v-stop">Allow? Run the iOS tests</span><span class="v-ans">xcodebuild test</span>',
             '<span class="v-base">&#10035; Working&#8230; (1m 12s)</span><span class="v-stop">Waiting on You.</span><span class="v-ans">&#10035; Running tests&#8230;</span>',
             '<span class="c-m base mi-happy"></span><span class="c-m alt mi-wait"></span>', 'sk-neon') +
        card('b', 'Fix the login bug', 'lostty/stay-awake', 'Editing StayAwakeController.swift', '&#10035; Incubating&#8230; (3m 52s)', '<span class="c-m base mi-happy"></span>', 'sk-sunset') +
        card('c', 'Deploy watch', 'home', 'Watching deploy.log', 'Ready.', '<span class="c-m base mi-ready"></span>', 'sk-deep') +
        card('d', 'api-server', 'api-server/main', '2h ago', 'Idle.', '<span class="c-m base mi-sleep"></span>', 'sk-silver')
    )

    keyrow = lambda ks, cls='': '<div class="krow %s">%s</div>' % (cls, ''.join('<span class="k%s">%s</span>' % (' k1' if k == '1' and cls == 'num' else '', k) for k in ks))
    kbd = ('<div class="kbd">'
           '<div class="krow acc"><span class="k">esc</span><span class="k">tab</span><span class="k">ctrl</span><span class="k">&#8593;</span><span class="k">&#8595;</span><span class="k">&#8592;</span><span class="k">&#8594;</span></div>'
           '<div class="krow num">' + ''.join('<span class="k%s">%s</span>' % (' k1' if k == '1' else '', k) for k in '1234567890') +
           '<span class="ktap"></span><span class="gapmark"><span class="s1t">Between 1 and 2</span><span class="s2t">Typed 1</span></span></div>'
           + keyrow('qwertyuiop') + keyrow('asdfghjkl') +
           '<div class="krow"><span class="k mod">&#8679;</span>' + ''.join('<span class="k">%s</span>' % k for k in 'zxcvbnm') + '<span class="k mod">&#9003;</span></div>'
           '<div class="krow"><span class="k mod">&#8963;</span><span class="k wide">space</span><span class="k ret">return</span></div>'
           '</div>')

    term = ('<div class="view view-term"><div class="t-head"><span class="back">&#8249;</span><span class="tt">Lostty UI redesign plan</span><span class="tp"><b>&gt;</b> lostty/skins</span></div>'
            '<div class="t-body"><span class="a">&gt;</span> make the skin picker remember\n  the last pane\n<span class="g">&#9210;</span> Update(App.swift) <span class="m">+18 &#8722;4</span>\n'
            '<span class="g">&#9210;</span> Bash(xcodebuild test\n    -scheme LosttyRemote)\n'
            '<span class="t-q"><span class="q">Do you want to proceed?\n<span class="sel">&#10095; 1. Yes</span>\n  2. Yes, and don&#8217;t ask again\n  3. No</span>\n<span class="a">&gt;</span> <span class="caret"></span></span>'
            '<span class="t-ans">  <span class="sel">&#10095; 1. Yes</span>\n<span class="a">&#10035;</span> Running tests&#8230; <span class="m">(0m 04s)</span>\n<span class="m">  Test Suite LosttyRemoteTests started</span></span>'
            '</div>' + kbd + '</div>')

    lst = ('<div class="view view-list"><div class="k-head">%s<h5>Lostty</h5><span class="kbtn">%s<span class="badge">1</span></span><span class="kbtn kb-plus">%s</span></div>'
           '<div class="conn">Connected <b><span class="n4">4</span><span class="n5">5</span></b></div>'
           '<div class="list">%s</div></div>') % (axo(cls='logo'), BELL, PLUS, cards)

    sheet_new = ('<div class="sh sh-new"><div class="grab"></div><h6>New session</h6>'
                 '<div class="lbl">Project folder on your Mac</div>'
                 '<div class="field">%s website</div>'
                 '<div class="folders"><div class="on">~/code/lostty/website</div><div>~/code/lostty</div><div>~/code/api-server</div></div>'
                 '<div class="lbl">Start</div><div class="seg3"><span class="on">Claude</span><span>Codex</span><span>Shell</span></div>'
                 '<div class="lbl">Model</div><div class="models"><span class="on">Opus</span><span>Sonnet</span><span>Haiku</span></div>'
                 '<div class="bigbtn">Start</div></div>') % SEARCH
    sheet_ok = ('<div class="sh sh-ok"><div class="grab"></div><span class="wait-tag"><i></i>Waiting on you</span>'
                '<h6>Lostty UI redesign plan</h6><div class="lbl">Allow? Run the iOS tests</div>'
                '<div class="cmd">$ xcodebuild test -scheme LosttyRemote</div>'
                '<div class="ok-row"><span>Deny</span><span class="allow">Allow</span></div></div>')

    phone = ('<div class="phone"><div class="screen"><div class="island"></div>'
             '<div class="sbar"><span>9:41</span><span class="sicons"><i class="sig"></i><i class="bat"></i></span></div>'
             + lst + term + sheet_ok + sheet_new +
             '<span class="tapr tap-plus"></span><span class="tapr tap-start"></span><span class="tapr tap-allow"></span>'
             '</div></div>')

    mbs = ('<div class="mb mb-wait"><span class="mi mi-wait"></span><i class="d"></i>Waiting on you</div>'
           '<div class="mb mb-snap"><span class="mi mi-happy"></span><i class="d"></i>Answered from the phone</div>'
           '<div class="mb mb-skin"><span class="mi mi-ready"></span><i class="d"></i>Four projects, four looks</div>'
           '<div class="mb mb-spawn"><span class="mi mi-happy"></span><i class="d"></i>Open on both, right now</div>'
           '<div class="mb mb-cheer"><span class="mi mi-happy"></span><i class="d"></i>Allowed. Claude carries on</div>')

    return ('<div class="rig %s" role="img" aria-label="%s"><div class="scene %s" aria-hidden="true">%s%s%s</div></div>'
            % (mode, label, flags, mac, phone, mbs))
