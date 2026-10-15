(function () {
  "use strict";
  var root = document.documentElement;
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");

  var FLAGS = ["stop", "rise", "wave", "term", "tap", "snap", "answered", "s1", "s2", "s3", "s4", "trace", "plus", "sheet", "spawn", "approve", "allowtap", "cheer"];
  function setFlags(scene, on) {
    for (var i = 0; i < FLAGS.length; i++) {
      scene.classList.toggle(FLAGS[i], on.indexOf(FLAGS[i]) !== -1);
    }
  }

  /* ---------- hero: a looping, time-based handoff ---------- */
  var HERO = [
    { f: [], t: 1700, k: "work", c: "Claude is working in lostty/skins." },
    { f: ["stop"], t: 1200, k: "wait", c: "Claude stopped to ask before running the iOS tests." },
    { f: ["stop", "rise", "wave"], t: 1900, k: "wait", c: "Your phone puts it first: Waiting on you." },
    { f: ["stop", "rise", "approve"], t: 1500, k: "wait", c: "Open it on the phone. Allow? Run the iOS tests." },
    { f: ["stop", "rise", "approve", "allowtap"], t: 900, k: "tap", c: "You tap Allow." },
    { f: ["rise", "answered", "cheer"], t: 2800, k: "work", c: "Claude carries on. The phone goes back in your pocket." }
  ];
  var heroScene = document.querySelector("#hero-rig .scene");
  var heroCap = document.getElementById("hero-caption");
  var heroCapText = heroCap ? heroCap.querySelector(".txt") : null;
  var heroIdx = 2, heroTimer = null, heroVisible = true;
  function heroShow(i) {
    var s = HERO[i];
    setFlags(heroScene, s.f);
    if (heroCap) { heroCap.setAttribute("data-k", s.k); heroCapText.textContent = s.c; }
  }
  function heroTick() {
    heroIdx = (heroIdx + 1) % HERO.length;
    heroShow(heroIdx);
    heroTimer = setTimeout(heroTick, HERO[heroIdx].t);
  }
  function heroStart() {
    if (heroTimer || reduce.matches || !heroVisible || document.hidden || !heroScene) return;
    heroTimer = setTimeout(heroTick, 900);
  }
  function heroStop() { clearTimeout(heroTimer); heroTimer = null; }
  if (heroScene) {
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        heroVisible = es[0].isIntersecting;
        if (heroVisible) heroStart(); else heroStop();
      }).observe(heroScene);
    }
    document.addEventListener("visibilitychange", function () { if (document.hidden) heroStop(); else heroStart(); });
    reduce.addEventListener && reduce.addEventListener("change", function () { if (reduce.matches) { heroStop(); heroIdx = 2; heroShow(2); } else heroStart(); });
    heroStart();
  }

  /* ---------- story: scroll progress drives the stage ---------- */
  var ALL = ["s1", "s2", "s3", "s4", "trace"];
  var BEATS = [
    [],
    ["stop"],
    ["stop", "rise", "wave"],
    ["stop", "rise", "term"],
    ["stop", "rise", "term", "tap"],
    ["rise", "term", "snap", "answered"],
    ["rise", "answered", "s1"],
    ["rise", "answered", "s1", "s2"],
    ["rise", "answered", "s1", "s2", "s3"],
    ["rise", "answered"].concat(ALL),
    ["rise", "answered", "plus"].concat(ALL),
    ["rise", "answered", "sheet"].concat(ALL),
    ["rise", "answered", "spawn"].concat(ALL)
  ];
  var RANGES = [[0, 3], [3, 3], [6, 4], [10, 3]];
  var stageMQ = window.matchMedia("(min-width: 960px)");
  var chapters = Array.prototype.slice.call(document.querySelectorAll(".ch"));
  var stageScene = document.querySelector("#stage-rig .scene");
  var segs = Array.prototype.slice.call(document.querySelectorAll(".seg"));
  var lastBeat = -1, ticking = false;

  function update() {
    ticking = false;
    if (!stageScene || !stageMQ.matches || document.body.classList.contains("view-docs")) return;
    var vh = window.innerHeight, mid = vh * 0.5, active = 0, beat = 0;
    for (var i = 0; i < chapters.length; i++) {
      var r = chapters[i].getBoundingClientRect();
      var p = Math.min(1, Math.max(0, (mid - r.top) / r.height));
      if (r.top <= mid) active = i;
      if (segs[i]) { segs[i].style.setProperty("--p", p.toFixed(3)); }
    }
    var ar = chapters[active].getBoundingClientRect();
    var ap = Math.min(0.999, Math.max(0, (mid - ar.top) / ar.height));
    var rg = RANGES[active];
    beat = rg[0] + Math.floor(ap * rg[1]);
    if (beat !== lastBeat) {
      lastBeat = beat;
      setFlags(stageScene, BEATS[beat]);
    }
    for (var j = 0; j < chapters.length; j++) {
      chapters[j].classList.toggle("is-active", j === active);
      if (segs[j]) segs[j].classList.toggle("on", j === active);
    }
  }
  function onScroll() { if (!ticking) { ticking = true; requestAnimationFrame(update); } }
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);
  stageMQ.addEventListener && stageMQ.addEventListener("change", onScroll);
  update();

  /* ---------- skins picker ---------- */
  var preview = document.getElementById("preview");
  var pvTex = preview ? preview.querySelector(".texture") : null;
  var pvName = document.getElementById("pv-name");
  var pvRar = document.getElementById("pv-rar");
  var pvDesc = document.getElementById("pv-desc");
  var pvCmd = document.getElementById("pv-cmd");
  var pvPill = document.getElementById("pv-pill");
  var picks = Array.prototype.slice.call(document.querySelectorAll(".pk"));
  function applySkin(btn) {
    if (!preview) return;
    var d = btn.dataset;
    preview.className = "preview " + d.sk;
    pvTex.className = "texture " + d.tx;
    pvName.textContent = d.id;
    pvRar.textContent = d.rar;
    pvRar.className = "rar " + d.rarc;
    pvDesc.textContent = d.desc;
    pvCmd.textContent = d.id;
    pvPill.textContent = d.path;
    picks.forEach(function (b) { b.setAttribute("aria-pressed", b === btn ? "true" : "false"); });
  }
  picks.forEach(function (b) {
    b.addEventListener("click", function () { applySkin(b); });
    b.addEventListener("mouseenter", function () { if (window.matchMedia("(hover: hover)").matches) applySkin(b); });
    b.addEventListener("focus", function () { applySkin(b); });
  });

  /* ---------- copy buttons ---------- */
  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var src = document.getElementById(btn.getAttribute("data-copy"));
      var text = src.getAttribute("data-text") || src.innerText;
      function done(ok) {
        btn.textContent = ok ? "Copied" : "Press ⌘C";
        btn.classList.toggle("done", ok);
        setTimeout(function () { btn.textContent = "Copy"; btn.classList.remove("done"); }, 1800);
      }
      function fallback() {
        try {
          var range = document.createRange();
          range.selectNodeContents(src);
          var sel = window.getSelection();
          sel.removeAllRanges(); sel.addRange(range);
          var ok = false;
          try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
          done(ok);
        } catch (e) { done(false); }
      }
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () { done(true); }, fallback);
        } else { fallback(); }
      } catch (e) { fallback(); }
    });
  });

  /* ---------- home / docs view ---------- */
  var navHome = document.querySelectorAll('.navlinks a[data-nav="docs"]');
  function route() {
    var h = (location.hash || "").slice(1);
    var docs = h === "docs" || h.indexOf("docs-") === 0;
    var was = document.body.classList.contains("view-docs");
    document.body.classList.toggle("view-docs", docs);
    navHome.forEach(function (a) {
      if (docs) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
    });
    if (docs) {
      var el = h === "docs" ? null : document.getElementById(h);
      if (el) { el.scrollIntoView({ behavior: "instant" }); } else if (!was) { window.scrollTo({ top: 0, behavior: "instant" }); }
    } else if (was) {
      var target = h ? document.getElementById(h) : null;
      if (target) target.scrollIntoView({ behavior: "instant" }); else window.scrollTo({ top: 0, behavior: "instant" });
    }
    lastBeat = -1; onScroll();
  }
  window.addEventListener("hashchange", route);
  route();

  /* docs on-this-page highlight */
  var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".dtoc a"));
  if ("IntersectionObserver" in window && tocLinks.length) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) {
          tocLinks.forEach(function (a) { a.classList.toggle("on", a.getAttribute("href") === "#" + e.target.id); });
        }
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    tocLinks.forEach(function (a) { var t = document.getElementById(a.getAttribute("href").slice(1)); if (t) io.observe(t); });
  }

  /* ---------- theme toggle ---------- */
  var tb = document.getElementById("themebtn");
  if (tb) {
    try { var saved = localStorage.getItem("lostty-theme"); if (saved) root.setAttribute("data-theme", saved); } catch (e) {}
    tb.addEventListener("click", function () {
      var cur = root.getAttribute("data-theme");
      if (!cur) cur = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
      var next = cur === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("lostty-theme", next); } catch (e) {}
    });
  }
})();
