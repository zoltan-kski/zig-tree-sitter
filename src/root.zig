// NOTE: remember to update the version numbers

/// The latest ABI version that is supported by the current version of the library.
///
/// The Tree-sitter library is generally backwards-compatible with
/// languages generated using older CLI versions, but is not forwards-compatible.
pub const LANGUAGE_VERSION = 14;

/// The earliest ABI version that is supported by the current version of the library.
pub const MIN_COMPATIBLE_LANGUAGE_VERSION = 13;

pub const set_allocator = @import("alloc.zig").ts_set_allocator;

const structs = @import("types.zig");
pub const Input = structs.Input;
pub const InputEdit = structs.InputEdit;
pub const InputEncoding = structs.InputEncoding;
pub const LogType = structs.LogType;
pub const Logger = structs.Logger;
pub const Point = structs.Point;
pub const Range = structs.Range;

pub const Language = @import("language.zig").Language;
pub const LookaheadIterator = @import("lookahead_iterator.zig").LookaheadIterator;
pub const Node = @import("node.zig").Node;
pub const Parser = @import("parser.zig").Parser;
pub const Query = @import("query.zig").Query;
pub const QueryCursor = @import("query_cursor.zig").QueryCursor;
pub const Tree = @import("tree.zig").Tree;
pub const TreeCursor = @import("tree_cursor.zig").TreeCursor;