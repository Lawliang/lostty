import type { Register } from 'claude-code'

// Lostty's prompt sharpener. In a Lostty pane with its switch on, each prompt you type is
// checked by a quick model; a sloppy one is rewritten in plain words before
// Claude reads it. Every prompt is logged through `lostty +sharpen-log`,
// which also tells the pane to show yours next to the rewrite. Any failure
// sends the prompt as typed.
// Design: docs/superpowers/specs/2026-11-13-lostty-prompt-sharpener-design.md

const CHECK_MODEL = 'haiku'
const REWRITE_MODEL = 'sonnet'
const CHECK_MS = 4000
const REWRITE_MS = 10000
const SHORT_WORDS = 4
const LONG_CHARS = 4000
const PASTE_LINES = 4
const CONTEXT_TURNS = 4
const CONTEXT_CHARS = 800

const TELLS = ['goal buried', 'no done check', 'filler', 'says the how', 'cause as fact', 'tangled asks']

const CHECK_SYSTEM = `You judge one prompt a developer typed to a coding agent. Is it sloppy?

A prompt is sloppy when one of these would make the agent misread it or wander:
- goal buried: the ask is hidden behind backstory ("so I've been noticing... anyway what I want is...")
- no done check: work is asked for with no way to tell it is finished ("make it better", "clean it up", "look into it")
- filler: dictation padding that blurs the ask ("go ahead and", "essentially", "you know", "like", "so basically")
- says the how: a step list or file-by-file recipe instead of the outcome
- cause as fact: a guess at the cause stated as known ("it's broken, it's the gesture code")
- tangled asks: several asks run together with "and also"

Not sloppy: a clear question ("why did BranchesModelTests fail on the last run?"), a clear short instruction ("merge main into this branch and rerun the build"), a follow-up that leans on the conversation, anything already direct. A question needs no done check. When unsure, it is not sloppy.

Answer with JSON only, no prose: {"slop": true or false, "tells": [the tells you found, by name]}`

const REWRITE_SYSTEM = `You rewrite a developer's sloppy prompt to a coding agent the way a senior engineer would type it. The result is still a normal chat message, not a document.

Voice:
- lowercase, short sentences, like a message to a teammate
- the goal in the first sentence: what is wrong, or what they want
- one done check that can fail; never "make it better"
- ask for proof when work is asked: "show me a recording", "show me before and after", "show me the passing run"
- limits as plain phrases: "repro first", "don't change any code yet", "let me review before you build", "zero behavior change"
- no headings, no labels like "Goal:", no bullets, no step lists; a few sentences at most

Put in: the goal, the done check, the proof, what they already know (a symptom, a log, a link), their real limits.
Leave out: the how, step lists, their guess at the cause, filler, backstory.
Never add a fact, file, number or requirement they did not say, and never drop one they did. Keep every path, file name, link, @mention, backticked text and number exactly as typed. Choices that are theirs stay open. Keep their names for things. If you cannot tell what they mean, return their prompt unchanged.

Lines in this voice:
- investigate why <symptom>. give me what we know, what data you used, and your best hypotheses. don't change any code yet.
- <operation> takes <time> on <fixture>. trace it, fix the measured cause, show me before and after.
- prototype a few options for <feature>. take screenshots for me to compare.
- move <code> into one module, zero behavior change. record the current output first and prove it's unchanged after.
- add <behavior>. <current output> stays byte-identical. verify both.
- <symptom>. repro first, then fix and verify.

Examples:
typed: the scroll thing is broken again can you look, i think its the gesture code
sent: scrolling is broken again. repro first, then fix it and show me a recording of it working.

typed: can you make the canvas faster its kind of laggy when theres a lot of cards, maybe cache stuff or something
sent: panning the canvas lags with a lot of cards open. measure it, fix the measured cause, and show me before and after.

typed: ok so basically i want you to go through all the tests and like make sure they're good and fix whatever's broken and also maybe clean up the old ones we don't need anymore
sent: run the test suite and fix what fails, then remove the tests we don't need anymore. show me the passing run and list what you removed.

typed: add dark mode to settings, first make a file called SettingsTheme.swift then add a struct with the colors then wire it into the view
sent: add dark mode to settings, with its colors in SettingsTheme.swift. show me a screenshot.

Answer with JSON only, no prose: {"prompt": "the rewritten prompt", "fixed": ["2-4 short labels for what you changed, like \\"goal first\\", \\"done check\\", \\"proof\\", \\"repro first\\", \\"−filler\\", \\"−cause guess\\", \\"−step list\\", \\"split asks\\""]}`

type Entry = {
  verdict: 'skipped' | 'clean' | 'rewritten' | 'failed'
  original: string
  sent: string
  rule?: string
  tells?: string[]
  fixed?: string[]
  error?: string
  checkMs?: number
  rewriteMs?: number
}

function skipRule(text: string, origin: string, isCommand: boolean, isMeta: boolean): { rule: string; send: string } | undefined {
  if (isCommand) return { rule: 'slash', send: text }
  if (isMeta) return { rule: 'meta', send: text }
  if (origin !== 'composer' && origin !== 'bridge') return { rule: 'origin', send: text }
  const trimmed = text.trim()
  if (/^raw:/i.test(trimmed)) return { rule: 'raw', send: trimmed.replace(/^raw:\s*/i, '') }
  if (trimmed.startsWith('<task-notification>')) return { rule: 'notice', send: text }
  if (trimmed.length > LONG_CHARS) return { rule: 'long', send: text }
  if (trimmed.includes('```') || trimmed.split('\n').length >= PASTE_LINES) return { rule: 'paste', send: text }
  if (trimmed.split(/\s+/).filter(Boolean).length <= SHORT_WORDS) return { rule: 'short', send: text }
  return undefined
}

// What a rewrite must keep exactly and may not invent: links, paths and
// file names, mentions, backticked code and numbers.
function anchors(text: string): Set<string> {
  const found = text.match(/https?:\/\/\S+|`[^`]+`|@[\w./-]+|[\w.-]*\/[\w./-]+|\b[\w-]+\.[A-Za-z]{1,5}\b|\b\d+(?:\.\d+)?\b/g) ?? []
  return new Set(found.map(t => t.replace(/[.,;:!?)]+$/, '')).filter(Boolean))
}

/// The first anchor the rewrite dropped or added, if any.
function changedAnchor(original: string, rewrite: string): string | undefined {
  const before = anchors(original)
  const after = anchors(rewrite)
  for (const a of before) if (!after.has(a)) return a
  for (const a of after) if (!before.has(a)) return a
  return undefined
}

function parseJson(text: string): Record<string, unknown> | undefined {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  const body = (fenced ? fenced[1] : text).trim()
  if (!body.startsWith('{')) return undefined
  try {
    const value = JSON.parse(body)
    return value && typeof value === 'object' && !Array.isArray(value) ? value : undefined
  } catch {
    return undefined
  }
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string').slice(0, 6) : []
}

export const register: Register = on => {
  on('prompt.submit', async ($, e, next) => {
    const pane = await $.env.get('LOSTTY_SURFACE')
    const bin = await $.env.get('LOSTTY_BIN')
    if (!pane || !bin) return next(e)

    const original = e.text
    const log = async (entry: Entry) => {
      const record = { ...entry, pane, session: await $.session.id(), cwd: await $.session.cwd(), origin: e.origin.kind }
      await $.process.run([bin, '+sharpen-log'], { stdin: JSON.stringify(record), timeoutMs: 3000 }).catch(() => undefined)
    }

    // Each terminal has its own switch on Lostty's bottom bar, off until
    // turned on: the app keeps a file per pane that has it on.
    const home = await $.env.get('HOME')
    const off = !(home && (await $.fs.exists(`${home}/Library/Application Support/Lostty/sharpener/on/${pane}`)))
    const skip = off ? { rule: 'off', send: original } : skipRule(original, e.origin.kind, e.command !== undefined, e.isMeta === true)
    if (skip) {
      await log({ verdict: 'skipped', original, sent: skip.send, rule: skip.rule })
      return skip.send === original ? next(e) : next({ ...e, text: skip.send })
    }

    // Only the owner's own earlier prompts: Claude's replies can quote
    // pages or files, which must not steer what is sent in the owner's name.
    const recent = await $.session.messages({ last: CONTEXT_TURNS })
    const context = Array.isArray(recent)
      ? recent.filter(m => m.role === 'user' && m.text).map(m => m.text.slice(0, CONTEXT_CHARS)).join('\n\n')
      : ''
    const framed = `${context ? `Their earlier prompts, for reference only (do not rewrite them):\n${context}\n\n` : ''}The prompt:\n${original}`

    const fail = async (error: string, extra: Partial<Entry> = {}) => {
      await log({ verdict: 'failed', original, sent: original, error, ...extra })
      return next(e)
    }

    const checkStart = await $.clock.now()
    const check = await $.model.complete({ model: CHECK_MODEL, system: CHECK_SYSTEM, prompt: framed, maxTokens: 200, effort: 'low', timeoutMs: CHECK_MS })
    const checkMs = (await $.clock.now()) - checkStart
    if (!check.isAnswered) return fail(`check: ${check.reason}`, { checkMs })
    const verdict = parseJson(check.text)
    if (!verdict || typeof verdict.slop !== 'boolean') return fail('check: no JSON', { checkMs })
    const tells = strings(verdict.tells).filter(t => TELLS.includes(t))
    if (!verdict.slop) {
      await log({ verdict: 'clean', original, sent: original, tells, checkMs })
      return next(e)
    }

    const rewriteStart = await $.clock.now()
    const rewrite = await $.model.complete({ model: REWRITE_MODEL, system: REWRITE_SYSTEM, prompt: `${framed}\n\nIts tells: ${tells.join(', ') || 'unclear'}`, maxTokens: 800, effort: 'low', timeoutMs: REWRITE_MS })
    const rewriteMs = (await $.clock.now()) - rewriteStart
    if (!rewrite.isAnswered) return fail(`rewrite: ${rewrite.reason}`, { tells, checkMs, rewriteMs })
    const result = parseJson(rewrite.text)
    const sent = typeof result?.prompt === 'string' ? result.prompt.trim() : ''
    if (!sent) return fail('rewrite: no prompt', { tells, checkMs, rewriteMs })
    const changed = changedAnchor(original, sent)
    if (changed) return fail(`rewrite: changed ${changed}`, { tells, checkMs, rewriteMs })
    if (sent === original.trim()) {
      await log({ verdict: 'clean', original, sent: original, tells, checkMs, rewriteMs })
      return next(e)
    }

    await log({ verdict: 'rewritten', original, sent, tells, fixed: strings(result?.fixed), checkMs, rewriteMs })
    return next({ ...e, text: sent })
  })
}
