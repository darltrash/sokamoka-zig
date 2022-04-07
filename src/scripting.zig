const std = @import("std");

//
// @playMusic "HAPPYSONG.mp3"
// : Main
//   - Hello!
//
//   ? Are you okay?
//   > Yes
//     - Oh that's pretty swell!
//
//   > Nah
//     - Hope things get better!
//
//   !
//
//   $ Main
// 

pub const TokenKinds = enum (u4) {
    Say, Ask, Jump, Call
};
pub const ValueKinds = enum(u4) {
    Number, Boolean, String, Label
};

const Opt = struct {
    title: []const u8,
    into: usize
};
const OptsArraylist = std.ArrayList(Opt);

pub const Value = union(ValueKinds) {
    Number: f32,
    Boolean: bool,
    String: []const u8,
    Label: usize,

    fn fromString(from: []const u8, at: *usize, allocator: std.mem.Allocator) !Value {
        while (from[at.*] < 33) {
            at.* += 1;
        }

        var buffer = std.ArrayList(u8).init(allocator);
        switch (from[at.*]) {
            48 ... 57 => {
                try buffer.append(from[at.*]);
                at.* += 1;
                while (from[at.*] > 33) {
                    try buffer.append(from[at.*]);
                    at.* += 1;
                }

                var raw = buffer.toOwnedSlice();
                var value = std.fmt.parseFloat(f32, raw) catch {
                    return error.InvalidNumber;
                };
                return Value {
                    .Number = value
                };
            },

            '"', '\'' => {
                var start = from[at.*];
                at.* += 1;

                while (from[at.*] != start) {
                    try buffer.append(from[at.*]);
                    at.* += 1;
                }

                var raw = buffer.toOwnedSlice();
                return Value {
                    .String = raw
                };
            },

            else => {
                if (std.mem.eql(u8, from[at.*..(at.*)+3], "yes"))
                    return Value { .Boolean = true  };

                if (std.mem.eql(u8, from[at.*..(at.*)+2], "no"))
                    return Value { .Boolean = false };
            
                return error.UnknownValueType;
            }
        }
        return error.UnknownValueType;
    }
};

pub const Token = union(TokenKinds) {
    Say: []const u8,
    Ask: struct {
        msg:  []const u8,
        opts: OptsArraylist,
        closed: bool = false
    },
    Jump: usize,
    Call: struct {
        what: []const u8,
        args: [][]const u8
    }
};

fn trimWhitespace(str: []const u8) []const u8 {
    return std.mem.trim(u8, std.mem.trim(u8, str, "\t"), " ");
}

pub fn tokenize(str: []const u8, allocator: std.mem.Allocator) ![]Token {
    var arrayList = std.ArrayList(Token).init(allocator);
    var lines = std.mem.tokenize(u8, str, "\n");
    var defined: usize = 0;

    var labels = std.StringHashMap(usize).init(allocator);

    while (lines.next()) |_line| {
        // I have absolutely no idea of what i'm doing
        var line = trimWhitespace(_line);
        line = line[0..(std.mem.indexOf(u8, line, "#") orelse line.len)];

        switch(line[0]) {
            '-' => {
                try arrayList.append(Token {
                    .Say = trimWhitespace(line[1..])
                });

                defined += 1;
            },

            '?' => {
                try arrayList.append(Token {
                    .Ask = .{
                        .msg = trimWhitespace(line[1..]),
                        .opts = OptsArraylist.init(allocator)
                    }
                });

                defined += 1;
            },
 
            '>' => {
                var done: bool = false;
                for (arrayList.items) |*token| {
                    if (token.* == .Ask) {
                        if (!token.*.Ask.closed) {
                            try token.Ask.opts.append(Opt {
                                .title = trimWhitespace(line[1..]),
                                .into = defined+1
                            });

                            done = true;
                            break;
                        }
                    }
                }

                if (!done)
                    return error.NoQuestionsOpen;
            },

            '!' => {
                var done: bool = false;
                for (arrayList.items) |*token| {
                    if (token.* == .Ask) {
                        if (!token.*.Ask.closed) {
                            token.Ask.closed = true;

                            done = true;
                            break;
                        }
                    }
                }

                if (!done)
                    return error.NoQuestionsOpen;
                
            },

            ':' => {
                try labels.put(trimWhitespace(line[1..]), defined);
            },

            '$' => {
                try arrayList.append(Token{
                    .Jump = labels.get(trimWhitespace(line[1..])) orelse return error.NoLabelAvailable
                });
            },

            '@' => {
                var at: usize = 0;
                while (at < line.len) {
                    std.log.info("{}", .{try Value.fromString(line[1..], &at, allocator)});
                }
            },

            else => unreachable
        }
    }
    return arrayList.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var tokens = try tokenize(
        \\  @2999999 "hello" 'jekyll'
        , allocator);
    std.log.info("{s}", .{tokens});
}