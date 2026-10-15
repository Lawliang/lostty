//! A small shell lexer for the guard: splits a command line into simple
//! commands (argv words, output-redirect targets, subshell depth). It reads
//! quotes, `$( )`, backticks, heredocs and comments the way sh does, and
//! marks any word whose value can't be known from the text as dynamic. It
//! decides nothing about danger. Anything it can't read is Unparseable,
//! which the guard treats as critical.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Word = struct {
    text: []const u8,
    dynamic: bool,
    /// Written `NAME=value`: an environment assignment when it leads a
    /// command, whatever its value (`BAR=$X git push`).
    assignment: bool = false,
};

pub const Command = struct {
    argv: []const Word,
    /// Output redirect targets (`>`, `>>`, `>|`, `&>`, `N>`), except
    /// `/dev/null` and `>&N`.
    writes: []const Word,
    /// How many `( )` subshells it's inside.
    depth: u8,
};

pub const Error = error{Unparseable} || Allocator.Error;

/// How deep `$( )`, backticks and `<( )` may nest before we give up.
const max_level = 32;

pub fn parse(alloc: Allocator, src: []const u8, home: []const u8) Error![]const Command {
    return parseAt(alloc, src, home, 0);
}

fn parseAt(alloc: Allocator, src: []const u8, home: []const u8, level: u8) Error![]const Command {
    var lx: Lexer = .{ .alloc = alloc, .src = src, .home = home, .level = level };
    try lx.run();
    return lx.out.toOwnedSlice(alloc);
}

const reserved_lead = [_][]const u8{ "if", "then", "else", "elif", "do", "while", "until", "!", "time", "{" };
const reserved_alone = [_][]const u8{ "fi", "done", "esac", "}" };

fn isOneOf(s: []const u8, list: []const []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, s, x)) return true;
    return false;
}

/// The raw text at `i` starts `NAME=` (before any quoting or expansion).
fn isAssignmentAt(src: []const u8, i: usize) bool {
    var j = i;
    while (j < src.len) : (j += 1) {
        const c = src[j];
        if (c == '=') return j > i;
        const ok = c == '_' or std.ascii.isAlphabetic(c) or (j > i and std.ascii.isDigit(c));
        if (!ok) return false;
    }
    return false;
}

const Heredoc = struct { delim: []const u8, strip_tabs: bool, quoted: bool };

/// `text` holds a command substitution (`$(`) or a backtick.
fn hasSubstitution(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "$(") != null or std.mem.indexOfScalar(u8, text, '`') != null;
}

/// `inner` (the text between the outer parens of `$(( … ))`) is one
/// parenthesised group, so the whole thing is arithmetic, not `$( (cmd); cmd )`.
fn isArithmetic(inner: []const u8) bool {
    if (inner.len < 2 or inner[0] != '(' or inner[inner.len - 1] != ')') return false;
    var level: usize = 0;
    for (inner, 0..) |c, j| {
        if (c == '(') level += 1;
        if (c == ')') {
            level -= 1;
            if (level == 0) return j == inner.len - 1;
        }
    }
    return false;
}

const Lexer = struct {
    alloc: Allocator,
    src: []const u8,
    home: []const u8,
    /// How many substitutions deep this lexer is.
    level: u8 = 0,
    i: usize = 0,
    depth: u8 = 0,
    /// The last word read contained a quote or backslash, so it can't be a
    /// keyword.
    last_quoted: bool = false,
    out: std.ArrayList(Command) = .empty,
    argv: std.ArrayList(Word) = .empty,
    writes: std.ArrayList(Word) = .empty,
    heredocs: std.ArrayList(Heredoc) = .empty,
    /// The next word is a redirect target: .write, .read, or .heredoc.
    pending: enum { none, write, read, heredoc, heredoc_dash } = .none,
    /// Inside `for … in …` up to `do`: words there aren't a command.
    in_for: bool = false,

    fn run(self: *Lexer) Error!void {
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            switch (c) {
                ' ', '\t' => self.i += 1,
                '\n' => {
                    try self.end();
                    self.i += 1;
                    try self.skipHeredocs();
                },
                '#' => {
                    // A comment only at the start of a word.
                    while (self.i < self.src.len and self.src[self.i] != '\n') self.i += 1;
                },
                ';', '&', '|' => try self.operator(),
                '\\' => {
                    if (self.i + 1 < self.src.len and self.src[self.i + 1] == '\n') {
                        self.i += 2; // line continuation between words
                    } else {
                        const w = try self.word();
                        try self.take(w);
                    }
                },
                '(' => {
                    try self.end();
                    if (self.depth == std.math.maxInt(u8)) return error.Unparseable;
                    self.depth += 1;
                    self.i += 1;
                },
                ')' => {
                    try self.end();
                    if (self.depth == 0) return error.Unparseable;
                    self.depth -= 1;
                    self.i += 1;
                },
                '<', '>' => try self.redirect(),
                else => {
                    // `2>` and `&>` start with a digit or `&`, handled here.
                    if (std.ascii.isDigit(c) and self.i + 1 < self.src.len and self.src[self.i + 1] == '>') {
                        self.i += 1;
                        try self.redirect();
                        continue;
                    }
                    const w = try self.word();
                    try self.take(w);
                },
            }
        }
        if (self.pending != .none) return error.Unparseable;
        if (self.heredocs.items.len != 0) return error.Unparseable;
        if (self.depth != 0) return error.Unparseable;
        try self.end();
    }

    fn operator(self: *Lexer) Error!void {
        const c = self.src[self.i];
        if (c == '&' and self.i + 1 < self.src.len and self.src[self.i + 1] == '>') {
            self.i += 1; // `&>`: a redirect, not background.
            return self.redirect();
        }
        if (c == ';' and self.i + 1 < self.src.len and self.src[self.i + 1] == ';') return error.Unparseable;
        try self.end();
        self.i += 1;
        if (self.i < self.src.len and (self.src[self.i] == c)) self.i += 1; // && ||
    }

    fn redirect(self: *Lexer) Error!void {
        const c = self.src[self.i];
        self.i += 1;
        if (c == '<') {
            if (self.i < self.src.len and self.src[self.i] == '<') {
                self.i += 1;
                if (self.i < self.src.len and self.src[self.i] == '<') {
                    self.i += 1; // <<< here-string: next word is data
                    self.pending = .read;
                    return;
                }
                if (self.i < self.src.len and self.src[self.i] == '-') {
                    self.i += 1;
                    self.pending = .heredoc_dash;
                } else self.pending = .heredoc;
                return;
            }
            if (self.i < self.src.len and self.src[self.i] == '(') return self.processSubst();
            if (self.i < self.src.len and self.src[self.i] == '&') {
                self.i += 1; // <&3: a descriptor
                self.skipDescriptor();
                return;
            }
            self.pending = .read;
            return;
        }
        // c == '>'
        if (self.i < self.src.len and (self.src[self.i] == '>' or self.src[self.i] == '|')) self.i += 1;
        if (self.i < self.src.len and self.src[self.i] == '&') {
            self.i += 1;
            // >&2 is a descriptor; >&file writes the file (like &>).
            if (self.i < self.src.len and (std.ascii.isDigit(self.src[self.i]) or self.src[self.i] == '-')) {
                self.skipDescriptor();
                return;
            }
            self.pending = .write;
            return;
        }
        if (self.i < self.src.len and self.src[self.i] == '(') return self.processSubst();
        self.pending = .write;
    }

    fn skipDescriptor(self: *Lexer) void {
        while (self.i < self.src.len and (std.ascii.isDigit(self.src[self.i]) or self.src[self.i] == '-')) self.i += 1;
    }

    fn processSubst(self: *Lexer) Error!void {
        const inner = try self.balanced('(', ')', true);
        try self.nested(inner);
        self.last_quoted = false;
        try self.take(.{ .text = "", .dynamic = true });
    }

    /// Takes a finished word: a redirect target, a heredoc delimiter, or an
    /// argument.
    fn take(self: *Lexer, w: Word) Error!void {
        switch (self.pending) {
            .write => {
                self.pending = .none;
                if (!std.mem.eql(u8, w.text, "/dev/null")) try self.writes.append(self.alloc, w);
                return;
            },
            .read => {
                self.pending = .none;
                return;
            },
            .heredoc, .heredoc_dash => {
                if (w.dynamic) return error.Unparseable;
                try self.heredocs.append(self.alloc, .{
                    .delim = w.text,
                    .strip_tabs = self.pending == .heredoc_dash,
                    .quoted = self.last_quoted,
                });
                self.pending = .none;
                return;
            },
            .none => {},
        }
        if (self.argv.items.len == 0) {
            // Only a bare word is a keyword; a quoted "for" or "case" is a command.
            const bare = !w.dynamic and !self.last_quoted;
            if (bare and std.mem.eql(u8, w.text, "case")) return error.Unparseable;
            if (bare and std.mem.eql(u8, w.text, "for")) {
                self.in_for = true;
                return;
            }
            if (self.in_for) {
                if (bare and std.mem.eql(u8, w.text, "do")) self.in_for = false;
                return;
            }
            if (bare and (isOneOf(w.text, &reserved_lead) or isOneOf(w.text, &reserved_alone))) return;
            if (w.assignment) return;
        }
        try self.argv.append(self.alloc, w);
    }

    fn end(self: *Lexer) Error!void {
        defer {
            self.argv = .empty;
            self.writes = .empty;
        }
        if (self.argv.items.len == 0 and self.writes.items.len == 0) return;
        try self.out.append(self.alloc, .{
            .argv = try self.argv.toOwnedSlice(self.alloc),
            .writes = try self.writes.toOwnedSlice(self.alloc),
            .depth = self.depth,
        });
    }

    /// After a newline, skips the bodies of heredocs opened on that line.
    fn skipHeredocs(self: *Lexer) Error!void {
        for (self.heredocs.items) |h| {
            const body_start = self.i;
            while (true) {
                if (self.i >= self.src.len) return error.Unparseable;
                const line_start = self.i;
                const eol = std.mem.indexOfScalarPos(u8, self.src, self.i, '\n') orelse self.src.len;
                var line = self.src[self.i..eol];
                if (h.strip_tabs) line = std.mem.trimLeft(u8, line, "\t");
                self.i = @min(eol + 1, self.src.len);
                if (std.mem.eql(u8, line, h.delim)) {
                    // An unquoted delimiter means the shell expands the body.
                    if (!h.quoted) try self.scanBody(self.src[body_start..line_start]);
                    break;
                }
            }
        }
        self.heredocs.clearRetainingCapacity();
    }

    /// Finds the `$( )` and backtick substitutions in an expanding heredoc
    /// body and appends their commands.
    fn scanBody(self: *Lexer, body: []const u8) Error!void {
        var sub: Lexer = .{ .alloc = self.alloc, .src = body, .home = self.home, .level = self.level, .depth = self.depth };
        while (sub.i < body.len) {
            switch (body[sub.i]) {
                '\\' => sub.i += 2,
                '$', '`' => try sub.expansion(),
                else => sub.i += 1,
            }
        }
        try self.out.appendSlice(self.alloc, sub.out.items);
    }

    /// Reads up to the matching `close`, honouring quotes and nesting. The
    /// opening char is at self.i. Returns the text between them.
    fn balanced(self: *Lexer, open: u8, close: u8, heredocs: bool) Error![]const u8 {
        std.debug.assert(self.src[self.i] == open);
        self.i += 1;
        const start = self.i;
        var level: usize = 1;
        while (self.i < self.src.len) : (self.i += 1) {
            const c = self.src[self.i];
            if (c == '\\') {
                self.i += 1;
            } else if (c == '\'') {
                self.i = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '\'') orelse return error.Unparseable;
            } else if (c == '"') {
                self.i = try self.skipDouble(self.i + 1);
            } else if (c == '$' and self.i + 1 < self.src.len and self.src[self.i + 1] == '\'') {
                self.i = try self.skipAnsi(self.i + 2);
            } else if (c == '<' and heredocs and open == '(' and self.i + 1 < self.src.len and self.src[self.i + 1] == '<') {
                if (self.i + 2 < self.src.len and self.src[self.i + 2] == '<') {
                    self.i += 2; // <<< here-string
                } else {
                    // A heredoc inside $( ): its body may hold quotes or parens.
                    self.i = try self.skipInnerHeredoc(self.i + 2);
                }
            } else if (c == open) {
                level += 1;
            } else if (c == close) {
                level -= 1;
                if (level == 0) {
                    const inner = self.src[start..self.i];
                    self.i += 1;
                    return inner;
                }
            }
        }
        return error.Unparseable;
    }

    /// Index of the closing `'` of a `$'…'` string whose body starts at
    /// `from`; a backslash escapes the next character.
    fn skipAnsi(self: *Lexer, from: usize) Error!usize {
        var j = from;
        while (j < self.src.len) : (j += 1) {
            switch (self.src[j]) {
                '\\' => j += 1,
                '\'' => return j,
                else => {},
            }
        }
        return error.Unparseable;
    }

    /// Index of the closing `"` of a double-quoted string starting at `from`.
    fn skipDouble(self: *Lexer, from: usize) Error!usize {
        var j = from;
        while (j < self.src.len) : (j += 1) {
            switch (self.src[j]) {
                '\\' => j += 1,
                '"' => return j,
                else => {},
            }
        }
        return error.Unparseable;
    }

    /// Skips `<<[-]DELIM … DELIM\n` inside a $( ); `from` is after `<<`.
    /// Returns the index of the last char of the closing delimiter line.
    fn skipInnerHeredoc(self: *Lexer, from: usize) Error!usize {
        var j = from;
        const dash = j < self.src.len and self.src[j] == '-';
        if (dash) j += 1;
        while (j < self.src.len and (self.src[j] == ' ' or self.src[j] == '\t')) j += 1;
        const dstart = j;
        while (j < self.src.len and self.src[j] != '\n' and self.src[j] != ' ' and self.src[j] != ')') j += 1;
        const delim = std.mem.trim(u8, self.src[dstart..j], "'\"");
        if (delim.len == 0) return j - 1;
        // Skip to the end of this line, then line by line to the delimiter.
        j = std.mem.indexOfScalarPos(u8, self.src, j, '\n') orelse return error.Unparseable;
        j += 1;
        while (j < self.src.len) {
            const eol = std.mem.indexOfScalarPos(u8, self.src, j, '\n') orelse self.src.len;
            var line = self.src[j..eol];
            if (dash) line = std.mem.trimLeft(u8, line, "\t");
            if (std.mem.eql(u8, line, delim)) return eol - 1;
            j = eol + 1;
        }
        return error.Unparseable;
    }

    /// Parses a $( ), backtick or <( ) body and appends its commands.
    fn nested(self: *Lexer, inner: []const u8) Error!void {
        if (self.level >= max_level) return error.Unparseable;
        const cmds = try parseAt(self.alloc, inner, self.home, self.level + 1);
        for (cmds) |c| try self.out.append(self.alloc, .{ .argv = c.argv, .writes = c.writes, .depth = c.depth +| self.depth });
    }

    /// One word, with quote removal. Stops at whitespace or an operator.
    fn word(self: *Lexer) Error!Word {
        var buf: std.ArrayList(u8) = .empty;
        var dynamic = false;
        const word_start = self.i;
        const assignment = isAssignmentAt(self.src, self.i);
        var quoted = false;
        defer self.last_quoted = quoted;
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            switch (c) {
                ' ', '\t', '\n', ';', '&', '|', '(', ')', '<', '>' => break,
                '\\' => {
                    quoted = true;
                    if (self.i + 1 < self.src.len) {
                        if (self.src[self.i + 1] != '\n') try buf.append(self.alloc, self.src[self.i + 1]);
                        self.i += 2;
                    } else self.i += 1;
                },
                '\'' => {
                    quoted = true;
                    const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '\'') orelse return error.Unparseable;
                    try buf.appendSlice(self.alloc, self.src[self.i + 1 .. close]);
                    self.i = close + 1;
                },
                '"' => {
                    quoted = true;
                    self.i += 1;
                    while (true) {
                        if (self.i >= self.src.len) return error.Unparseable;
                        const d = self.src[self.i];
                        if (d == '"') {
                            self.i += 1;
                            break;
                        }
                        if (d == '\\' and self.i + 1 < self.src.len) {
                            try buf.append(self.alloc, self.src[self.i + 1]);
                            self.i += 2;
                        } else if (d == '$' or d == '`') {
                            dynamic = true;
                            try self.expansion();
                        } else {
                            try buf.append(self.alloc, d);
                            self.i += 1;
                        }
                    }
                },
                '$', '`' => {
                    if (c == '$' and self.i + 1 < self.src.len and self.src[self.i + 1] == '\'') {
                        // $'…': ANSI-C quoting. Escapes make the value unknowable here.
                        quoted = true;
                        const close = try self.skipAnsi(self.i + 2);
                        const raw = self.src[self.i + 2 .. close];
                        if (std.mem.indexOfScalar(u8, raw, '\\') != null) {
                            dynamic = true;
                        } else {
                            try buf.appendSlice(self.alloc, raw);
                        }
                        self.i = close + 1;
                    } else {
                        dynamic = true;
                        try self.expansion();
                    }
                },
                '{' => {
                    // Brace expansion (`{a,b}`, `{1..3}`, no spaces inside)
                    // makes several words; we can't know them. A `{ …; }`
                    // group has spaces and is a keyword, not this.
                    if (std.mem.indexOfScalarPos(u8, self.src, self.i, '}')) |close| {
                        const inside_braces = self.src[self.i..close];
                        if (std.mem.indexOfAny(u8, inside_braces, " \t\n") == null and
                            std.mem.indexOfAny(u8, inside_braces, ",.") != null) dynamic = true;
                    }
                    try buf.append(self.alloc, c);
                    self.i += 1;
                },
                else => {
                    try buf.append(self.alloc, c);
                    self.i += 1;
                },
            }
        }
        var text = try buf.toOwnedSlice(self.alloc);
        // An unquoted leading ~ is the home folder.
        if (self.src[word_start] == '~' and (text.len == 1 or text[1] == '/')) {
            text = try std.mem.concat(self.alloc, u8, &.{ self.home, text[1..] });
        }
        if (dynamic) text = "";
        return .{ .text = text, .dynamic = dynamic, .assignment = assignment };
    }

    /// `$NAME`, `${…}`, `$( )`, `` `…` ``, `$((…))`: commands inside are
    /// parsed and appended; the value itself is unknown.
    fn expansion(self: *Lexer) Error!void {
        const c = self.src[self.i];
        if (c == '`') {
            const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '`') orelse return error.Unparseable;
            const inner = self.src[self.i + 1 .. close];
            self.i = close + 1;
            return self.nested(inner);
        }
        // c == '$'
        self.i += 1;
        if (self.i >= self.src.len) return;
        switch (self.src[self.i]) {
            '(' => {
                if (self.i + 1 < self.src.len and self.src[self.i + 1] == '(') {
                    const inner = try self.balanced('(', ')', false);
                    if (!isArithmetic(inner)) return self.nested(inner); // `$((cmd); cmd)`
                    if (hasSubstitution(inner)) return error.Unparseable;
                    return;
                }
                const inner = try self.balanced('(', ')', true);
                return self.nested(inner);
            },
            '{' => {
                // Substitutions inside `${X:-$(cmd)}` aren't followed; refuse.
                const inner = try self.balanced('{', '}', false);
                if (hasSubstitution(inner)) return error.Unparseable;
            },
            else => while (self.i < self.src.len and (std.ascii.isAlphanumeric(self.src[self.i]) or self.src[self.i] == '_' or
                (self.i > 0 and self.src[self.i - 1] == '$' and std.mem.indexOfScalar(u8, "@*#?$!-0123456789", self.src[self.i]) != null)))
            {
                self.i += 1;
            },
        }
    }
};

fn texts(alloc: Allocator, cmd: Command) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (cmd.argv) |w| try out.append(alloc, w.text);
    return out.toOwnedSlice(alloc);
}

fn expectArgv(cmd: Command, want: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try texts(arena.allocator(), cmd);
    try std.testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try std.testing.expectEqualStrings(w, g);
}

test "guard shell: splits on operators, keeps quoted ones" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "echo \"a; rm -rf x\" && grep -E 'a|b' f; ls | wc -l & true\nfalse", "/home/me");
    try std.testing.expectEqual(@as(usize, 6), cmds.len);
    try expectArgv(cmds[0], &.{ "echo", "a; rm -rf x" });
    try expectArgv(cmds[1], &.{ "grep", "-E", "a|b", "f" });
    try expectArgv(cmds[2], &.{"ls"});
    try expectArgv(cmds[3], &.{ "wc", "-l" });
    try expectArgv(cmds[4], &.{"true"});
    try expectArgv(cmds[5], &.{"false"});
}

test "guard shell: heredoc bodies aren't commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src =
        \\git commit -m "$(cat <<'EOF'
        \\Stop rm -rf build; from running
        \\EOF
        \\)" && echo ok
    ;
    const cmds = try parse(arena.allocator(), src, "/home/me");
    // The inner cat (appended as soon as it's read), git, echo; nothing
    // from the body.
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    for (cmds) |c| {
        try std.testing.expect(!std.mem.eql(u8, c.argv[0].text, "rm"));
        try std.testing.expect(!std.mem.eql(u8, c.argv[0].text, "Stop"));
    }
    try expectArgv(cmds[0], &.{"cat"});
    try std.testing.expectEqualStrings("git", cmds[1].argv[0].text);
    try std.testing.expect(cmds[1].argv[3].dynamic); // the $( ) message
    try expectArgv(cmds[2], &.{ "echo", "ok" });
}

test "guard shell: plain heredoc with a dash and tabs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "cat <<-END > out.txt\n\trm -rf /\n\tEND\nls", "/h");
    try std.testing.expectEqual(@as(usize, 2), cmds.len);
    try expectArgv(cmds[0], &.{"cat"});
    try std.testing.expectEqualStrings("out.txt", cmds[0].writes[0].text);
    try expectArgv(cmds[1], &.{"ls"});
}

test "guard shell: command substitutions become their own commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "echo $(rm -rf x) `unlink y`", "/h");
    // Inner commands are appended as they're read, before the outer one ends.
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    try expectArgv(cmds[0], &.{ "rm", "-rf", "x" });
    try expectArgv(cmds[1], &.{ "unlink", "y" });
    try expectArgv(cmds[2], &.{ "echo", "", "" });
    try std.testing.expect(cmds[2].argv[1].dynamic);
}

test "guard shell: variables, braces and tilde" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "rm $DIR/a ${X} {a,b} ~/notes '~/lit' \"$HOME\"", "/home/me");
    const argv = cmds[0].argv;
    try std.testing.expect(argv[1].dynamic);
    try std.testing.expect(argv[2].dynamic);
    try std.testing.expect(argv[3].dynamic);
    try std.testing.expectEqualStrings("/home/me/notes", argv[4].text);
    try std.testing.expect(!argv[4].dynamic);
    try std.testing.expectEqualStrings("~/lit", argv[5].text);
    try std.testing.expect(argv[6].dynamic);
}

test "guard shell: redirects are writes, not arguments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "make 2>&1 >log.txt 2>/dev/null >> ~/x &> all < in.txt", "/home/me");
    try expectArgv(cmds[0], &.{"make"});
    const w = cmds[0].writes;
    try std.testing.expectEqual(@as(usize, 3), w.len);
    try std.testing.expectEqualStrings("log.txt", w[0].text);
    try std.testing.expectEqualStrings("/home/me/x", w[1].text);
    try std.testing.expectEqualStrings("all", w[2].text);
}

test "guard shell: subshells and groups set depth, keywords drop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "(cd sub && make); if test -f x; then rm x; fi; for f in *.log; do rm \"$f\"; done", "/h");
    try expectArgv(cmds[0], &.{ "cd", "sub" });
    try std.testing.expectEqual(@as(u8, 1), cmds[0].depth);
    try expectArgv(cmds[1], &.{"make"});
    try std.testing.expectEqual(@as(u8, 1), cmds[1].depth);
    try expectArgv(cmds[2], &.{ "test", "-f", "x" });
    try std.testing.expectEqual(@as(u8, 0), cmds[2].depth);
    try expectArgv(cmds[3], &.{ "rm", "x" });
    try expectArgv(cmds[4], &.{ "rm", "" });
    try std.testing.expect(cmds[4].argv[1].dynamic);
    try std.testing.expectEqual(@as(usize, 5), cmds.len);
}

test "guard shell: env assignments and comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parse(arena.allocator(), "FOO=1 BAR=$X git push # rm -rf /", "/h");
    try std.testing.expectEqual(@as(usize, 1), cmds.len);
    try expectArgv(cmds[0], &.{ "git", "push" });
}

test "guard shell: unbalanced quotes and case are unparseable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.Unparseable, parse(a, "echo \"oops", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "echo $(ls", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "case $x in a) rm y;; esac", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "cat <<EOF\nno end", "/h"));
}

fn parseOk(arena: *std.heap.ArenaAllocator, src: []const u8) ![]const Command {
    return parse(arena.allocator(), src, "/h");
}

fn hasCommand(cmds: []const Command, name: []const u8) bool {
    for (cmds) |c| if (c.argv.len > 0 and std.mem.eql(u8, c.argv[0].text, name)) return true;
    return false;
}

test "guard shell: commands inside ${ } and $(( )) are found or refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.Unparseable, parse(a, "echo ${X:-$(rm -rf x)}", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "echo ${X:-`rm x`}", "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "echo $(( $(rm x) + 1 ))", "/h"));
    // Not arithmetic: bash runs it as $( (rm x); ls ).
    const cmds = try parseOk(&arena, "echo $((rm x); ls)");
    try std.testing.expect(hasCommand(cmds, "rm"));
    try std.testing.expect(hasCommand(cmds, "ls"));
    // Plain arithmetic and expansions stay quiet.
    const ok = try parseOk(&arena, "echo $((1<<2)) $(( (1+2)*3 )) ${X:-y}");
    try std.testing.expectEqual(@as(usize, 1), ok.len);
    try std.testing.expect(ok[0].argv[1].dynamic);
}

test "guard shell: unquoted heredoc bodies expand, quoted ones don't" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = try parseOk(&arena, "cat <<EOF\nhi $(rm -rf x) and `unlink y`\nEOF\nls");
    try std.testing.expect(hasCommand(a, "rm"));
    try std.testing.expect(hasCommand(a, "unlink"));
    try std.testing.expect(hasCommand(a, "cat"));
    try std.testing.expect(hasCommand(a, "ls"));
    const q = try parseOk(&arena, "cat <<'EOF'\n$(rm -rf x)\nEOF");
    try std.testing.expectEqual(@as(usize, 1), q.len);
    const e = try parseOk(&arena, "cat <<\\EOF\n$(rm -rf x)\nEOF");
    try std.testing.expectEqual(@as(usize, 1), e.len);
    // Inside a $( ), too.
    const n = try parseOk(&arena, "echo $(cat <<EOF\n$(rm x)\nEOF\n)");
    try std.testing.expect(hasCommand(n, "rm"));
}

test "guard shell: <<< and << inside substitutions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parseOk(&arena, "echo $(cat <<< hi; rm x)");
    try std.testing.expect(hasCommand(cmds, "cat"));
    try std.testing.expect(hasCommand(cmds, "rm"));
    const arith = try parseOk(&arena, "echo $((1<<2))");
    try std.testing.expectEqual(@as(usize, 1), arith.len);
}

test "guard shell: a quoted keyword is a command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const f = try parseOk(&arena, "\"for\" x; rm -rf /");
    try std.testing.expectEqual(@as(usize, 2), f.len);
    try expectArgv(f[0], &.{ "for", "x" });
    try expectArgv(f[1], &.{ "rm", "-rf", "/" });
    const t = try parseOk(&arena, "'then' rm x; \\fi");
    try expectArgv(t[0], &.{ "then", "rm", "x" });
    try expectArgv(t[1], &.{"fi"});
    try std.testing.expectError(error.Unparseable, parse(arena.allocator(), "case x in", "/h"));
    // A quoted `case` is just a command.
    const c = try parseOk(&arena, "'case' x");
    try expectArgv(c[0], &.{ "case", "x" });
}

test "guard shell: ANSI-C quotes don't end early" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parseOk(&arena, "echo $'\\'' ; rm -rf /; echo 'x'");
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    try expectArgv(cmds[0], &.{ "echo", "" });
    try std.testing.expect(cmds[0].argv[1].dynamic);
    try expectArgv(cmds[1], &.{ "rm", "-rf", "/" });
    // The reviewer's input ends in a stray quote: unterminated, so refused.
    try std.testing.expectError(error.Unparseable, parse(arena.allocator(), "echo $'\\'' ; rm -rf /; echo '", "/h"));
    const plain = try parseOk(&arena, "echo $'a b'");
    try expectArgv(plain[0], &.{ "echo", "a b" });
    try std.testing.expectError(error.Unparseable, parse(arena.allocator(), "echo $'oops", "/h"));
}

test "guard shell: >&file is a write, >&2 is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cmds = try parseOk(&arena, "echo hi >&out.txt; echo err >&2; cat <&3");
    try expectArgv(cmds[0], &.{ "echo", "hi" });
    try std.testing.expectEqualStrings("out.txt", cmds[0].writes[0].text);
    try expectArgv(cmds[1], &.{ "echo", "err" });
    try std.testing.expectEqual(@as(usize, 0), cmds[1].writes.len);
    try std.testing.expectEqual(@as(usize, 3), cmds.len);
    try expectArgv(cmds[2], &.{"cat"});
}

test "guard shell: absurd nesting is unparseable, not a crash" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const open = "$(" ** 40;
    const close = ")" ** 40;
    try std.testing.expectError(error.Unparseable, parse(a, "echo " ++ open ++ "ls" ++ close, "/h"));
    try std.testing.expectError(error.Unparseable, parse(a, "(" ** 300 ++ "ls" ++ ")" ** 300, "/h"));
    // Reasonable nesting still works.
    const ok = try parse(a, "echo $(echo $(echo $(ls)))", "/h");
    try std.testing.expectEqual(@as(usize, 4), ok.len);
}

test "guard shell: groups, process substitution, nested quotes, continuations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const g = try parseOk(&arena, "{ rm x; ls; }");
    try std.testing.expectEqual(@as(usize, 2), g.len);
    try expectArgv(g[0], &.{ "rm", "x" });
    try expectArgv(g[1], &.{"ls"});

    const p = try parseOk(&arena, "diff <(sort a) <(rm b; sort c)");
    try std.testing.expect(hasCommand(p, "sort"));
    try std.testing.expect(hasCommand(p, "rm"));
    const diff = p[p.len - 1];
    try expectArgv(diff, &.{ "diff", "", "" });
    try std.testing.expect(diff.argv[1].dynamic);

    const q = try parseOk(&arena, "echo $(echo \"a ) b\" 'c )' && rm x)");
    try std.testing.expectEqual(@as(usize, 3), q.len);
    try expectArgv(q[0], &.{ "echo", "a ) b", "c )" });
    try expectArgv(q[1], &.{ "rm", "x" });

    const c = try parseOk(&arena, "rm \\\n -rf x");
    try std.testing.expectEqual(@as(usize, 1), c.len);
    try expectArgv(c[0], &.{ "rm", "-rf", "x" });
}
