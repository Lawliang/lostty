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

pub fn parse(alloc: Allocator, src: []const u8, home: []const u8) Error![]const Command {
    var lx: Lexer = .{ .alloc = alloc, .src = src, .home = home };
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

const Heredoc = struct { delim: []const u8, strip_tabs: bool };

const Lexer = struct {
    alloc: Allocator,
    src: []const u8,
    home: []const u8,
    i: usize = 0,
    depth: u8 = 0,
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
                '(' => {
                    try self.end();
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
            self.pending = .read;
            return;
        }
        // c == '>'
        if (self.i < self.src.len and (self.src[self.i] == '>' or self.src[self.i] == '|')) self.i += 1;
        if (self.i < self.src.len and self.src[self.i] == '&') {
            // >&2: a descriptor, not a file.
            self.i += 1;
            while (self.i < self.src.len and (std.ascii.isDigit(self.src[self.i]) or self.src[self.i] == '-')) self.i += 1;
            return;
        }
        if (self.i < self.src.len and self.src[self.i] == '(') return self.processSubst();
        self.pending = .write;
    }

    fn processSubst(self: *Lexer) Error!void {
        const inner = try self.balanced('(', ')');
        try self.nested(inner);
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
                try self.heredocs.append(self.alloc, .{ .delim = w.text, .strip_tabs = self.pending == .heredoc_dash });
                self.pending = .none;
                return;
            },
            .none => {},
        }
        if (self.argv.items.len == 0) {
            if (std.mem.eql(u8, w.text, "case")) return error.Unparseable;
            if (std.mem.eql(u8, w.text, "for")) {
                self.in_for = true;
                return;
            }
            if (self.in_for) {
                if (std.mem.eql(u8, w.text, "do")) self.in_for = false;
                return;
            }
            if (!w.dynamic and isOneOf(w.text, &reserved_lead)) return;
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
        if (self.argv.items.len == 1 and isOneOf(self.argv.items[0].text, &reserved_alone)) return;
        try self.out.append(self.alloc, .{
            .argv = try self.argv.toOwnedSlice(self.alloc),
            .writes = try self.writes.toOwnedSlice(self.alloc),
            .depth = self.depth,
        });
    }

    /// After a newline, skips the bodies of heredocs opened on that line.
    fn skipHeredocs(self: *Lexer) Error!void {
        for (self.heredocs.items) |h| {
            while (true) {
                if (self.i >= self.src.len) return error.Unparseable;
                const eol = std.mem.indexOfScalarPos(u8, self.src, self.i, '\n') orelse self.src.len;
                var line = self.src[self.i..eol];
                if (h.strip_tabs) line = std.mem.trimLeft(u8, line, "\t");
                self.i = @min(eol + 1, self.src.len);
                if (std.mem.eql(u8, line, h.delim)) break;
            }
        }
        self.heredocs.clearRetainingCapacity();
    }

    /// Reads up to the matching `close`, honouring quotes and nesting. The
    /// opening char is at self.i. Returns the text between them.
    fn balanced(self: *Lexer, open: u8, close: u8) Error![]const u8 {
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
            } else if (c == '<' and self.i + 1 < self.src.len and self.src[self.i + 1] == '<' and open == '(') {
                // A heredoc inside $( ): its body may hold quotes or parens.
                self.i = try self.skipInnerHeredoc(self.i + 2);
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
        const cmds = try parse(self.alloc, inner, self.home);
        for (cmds) |c| try self.out.append(self.alloc, .{ .argv = c.argv, .writes = c.writes, .depth = c.depth + self.depth });
    }

    /// One word, with quote removal. Stops at whitespace or an operator.
    fn word(self: *Lexer) Error!Word {
        var buf: std.ArrayList(u8) = .empty;
        var dynamic = false;
        const word_start = self.i;
        const assignment = isAssignmentAt(self.src, self.i);
        while (self.i < self.src.len) {
            const c = self.src[self.i];
            switch (c) {
                ' ', '\t', '\n', ';', '&', '|', '(', ')', '<', '>' => break,
                '\\' => {
                    if (self.i + 1 < self.src.len) {
                        if (self.src[self.i + 1] != '\n') try buf.append(self.alloc, self.src[self.i + 1]);
                        self.i += 2;
                    } else self.i += 1;
                },
                '\'' => {
                    const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 1, '\'') orelse return error.Unparseable;
                    try buf.appendSlice(self.alloc, self.src[self.i + 1 .. close]);
                    self.i = close + 1;
                },
                '"' => {
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
                    dynamic = true;
                    try self.expansion();
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
                    _ = try self.balanced('(', ')'); // arithmetic: no commands
                    return;
                }
                const inner = try self.balanced('(', ')');
                return self.nested(inner);
            },
            '{' => _ = try self.balanced('{', '}'),
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
