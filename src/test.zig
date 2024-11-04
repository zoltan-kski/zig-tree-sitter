const std = @import("std");
const testing = std.testing;
const ts = @import("root.zig");

test "Language" {
    const language = ts.Language.load("c");
    defer language.destroy();

    try testing.expectEqual(14, language.version());
    try testing.expect(language.symbolCount() > 1);
    try testing.expect(language.fieldCount() > 1);
    try testing.expect(language.stateCount() > 1);
    try testing.expect(language.fieldIdForName("body") > 0);
    try testing.expect(language.fieldNameForId(1) != null);
    try testing.expectEqual(161, language.symbolForName("translation_unit", true));
    try testing.expectEqualStrings("identifier", language.symbolName(1) orelse "");
    try testing.expect(language.isNamed(1));
    try testing.expect(language.isVisible(1));
    try testing.expect(!language.isSupertype(1));
    try testing.expect(language.nextState(1, 161) > 1);

    const copy = language.dupe();
    try testing.expectEqual(language, copy);
    copy.destroy();
}

test "LookaheadIterator" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const state = language.nextState(1, 161);
    const lookahead = ts.LookaheadIterator.create(language, state).?;
    defer lookahead.destroy();

    try testing.expectEqual(language, lookahead.language());
    try testing.expectEqual(0xFFFF, lookahead.currentSymbol());
    try testing.expectEqualStrings("ERROR", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(160, lookahead.currentSymbol());
    try testing.expectEqualStrings("comment", lookahead.currentSymbolName());

    try testing.expect(lookahead.next());
    try testing.expectEqual(0, lookahead.currentSymbol());
    try testing.expectEqualStrings("end", lookahead.currentSymbolName());

    try testing.expect(!lookahead.next());
    try testing.expect(lookahead.resetState(state));

    try testing.expect(lookahead.next());
    try testing.expect(lookahead.reset(language, state));
}

test "Parser" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    try testing.expectEqual(language, parser.getLanguage());
    try testing.expectEqual(null, parser.getLogger().log);
    try testing.expectEqual(0, parser.getTimeoutMicros());
    try testing.expectEqual(null, parser.getCancellationFlag());

    try testing.expectEqualSlices(ts.Range, &.{ .{} }, parser.getIncludedRanges());
    try testing.expectError(error.RangeOverlap, parser.setIncludedRanges(&.{ .{ .start_byte = 1 }, .{} }));

    // TODO: more tests
}

test "Tree" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = try parser.parseBuffer("int main() {}", null, .UTF_8);
    defer tree.destroy();
    try testing.expectEqual(language, tree.language());
    try testing.expectEqual(13, tree.rootNode().endByte());
    try testing.expectEqual(3, tree.rootNodeWithOffset(3, .{ .row = 0, .column = 3 }).?.startByte());

    var ranges = tree.getIncludedRanges();
    var range: ts.Range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0xFFFFFFFF, .column = 0xFFFFFFFF },
        .start_byte = 0,
        .end_byte = 0xFFFFFFFF
    };
    try testing.expectEqualSlices(ts.Range, &.{ range }, ranges);
    ts.Tree.freeRanges(ranges);

    const old_tree = tree.dupe();
    try testing.expect(tree != old_tree);
    defer old_tree.destroy();

    old_tree.edit(.{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    });
    const new_tree = try parser.parseBuffer("main() {}", old_tree, .UTF_8);
    defer new_tree.destroy();
    range = .{
        .start_point = .{ .row = 0, .column = 0 },
        .end_point = .{ .row = 0, .column = 9 },
        .start_byte = 0,
        .end_byte = 9
    };
    ranges = old_tree.getChangedRanges(new_tree);
    try testing.expectEqualSlices(ts.Range, &.{ range }, ranges);
    ts.Tree.freeRanges(ranges);
}

test "TreeCursor" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = try parser.parseBuffer("int main() {}", null, .UTF_8);
    defer tree.destroy();
    const root_node = tree.rootNode();

    var cursor = ts.TreeCursor.create(root_node);
    defer cursor.destroy();

    var node = cursor.currentNode();
    try testing.expect(node.eql(root_node));
    try testing.expectEqual(node, cursor.currentNode());

    var copy = cursor.dupe();
    try testing.expect(cursor.id != copy.id);
    try testing.expectEqual(cursor.tree, copy.tree);

    cursor.resetTo(&copy);
    try testing.expectEqual(copy.currentNode(), cursor.currentNode());
    copy.destroy();

    try testing.expect(cursor.gotoFirstChild());
    try testing.expectEqualStrings("function_definition", cursor.currentNode().@"type"());
    try testing.expectEqual(1, cursor.currentDepth());

    try testing.expect(cursor.gotoLastChild());
    try testing.expectEqualStrings("compound_statement", cursor.currentNode().@"type"());
    try testing.expectEqualStrings("body", cursor.currentFieldName().?);

    try testing.expect(cursor.gotoParent());
    try testing.expectEqualStrings("function_definition", cursor.currentNode().@"type"());
    try testing.expectEqual(0, cursor.currentFieldId());

    try testing.expect(!cursor.gotoNextSibling());
    try testing.expect(!cursor.gotoPreviousSibling());

    cursor.gotoDescendant(2);
    try testing.expectEqual(2, cursor.currentDescendantIndex());
    cursor.reset(root_node);

    try testing.expectEqual(0, cursor.gotoFirstChildForByte(1));
    try testing.expectEqual(1, cursor.gotoFirstChildForPoint(.{ .row = 0, .column = 5 }));
    try testing.expectEqualStrings("declarator", cursor.currentFieldName().?);
}

test "Node" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = try parser.parseBuffer("int main() {}", null, .UTF_8);
    defer tree.destroy();
    var node = tree.rootNode();

    try testing.expectEqual(tree, node.tree);
    try testing.expectEqual(tree.language(), node.language());

    try testing.expectEqual(161, node.symbol());
    try testing.expectEqual(161, node.grammarSymbol());
    try testing.expectEqualStrings("translation_unit", node.@"type"());
    try testing.expectEqualStrings("translation_unit", node.grammarType());

    try testing.expect(node.isNamed());
    try testing.expect(!node.isExtra());
    try testing.expect(!node.isError());
    try testing.expect(!node.isMissing());

    try testing.expectEqual(0, node.parseState());
    try testing.expectEqual(0, node.nextParseState());

    try testing.expectEqual(0, node.startByte());
    try testing.expectEqual(13, node.endByte());
    try testing.expectEqual(0, node.startPoint().column);
    try testing.expectEqual(13, node.endPoint().column);

    try testing.expectEqual(1, node.childCount());
    try testing.expectEqual(1, node.namedChildCount());
    try testing.expectEqual(11, node.descendantCount());

    node = node.child(0).?;
    try testing.expectEqual(tree.rootNode(), node.parent());
    try testing.expectEqualStrings("function_declarator", node.namedChild(1).?.@"type"());
    try testing.expectEqual(null, node.childByFieldId(1));
    try testing.expectEqualStrings("primitive_type", node.childByFieldName("type").?.@"type"());

    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextSibling().?.@"type"());
    try testing.expectEqualStrings("function_declarator", node.child(0).?.nextNamedSibling().?.@"type"());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevSibling().?.@"type"());
    try testing.expectEqualStrings("function_declarator", node.child(2).?.prevNamedSibling().?.@"type"());

    try testing.expectEqual(node, tree.rootNode().childWithDescendant(node));
    try testing.expectEqualStrings("{", node.descendantForByteRange(11, 12).?.@"type"());
    try testing.expectEqualStrings("compound_statement", node.namedDescendantForByteRange(11, 12).?.@"type"());

    const points: [2]ts.Point = .{ .{ .row = 0, .column = 4 }, .{ .row = 0, .column = 8 }};
    try testing.expectEqualStrings("identifier", node.descendantForPointRange(points[0], points[1]).?.@"type"());
    try testing.expectEqualStrings("identifier", node.namedDescendantForPointRange(points[0], points[1]).?.@"type"());

    try testing.expectEqualStrings("body", node.fieldNameForChild(2).?);
    try testing.expectEqualStrings("body", node.fieldNameForNamedChild(2).?);

    const sexp = node.toSexp();
    defer ts.Node.freeSexp(sexp);
    try testing.expectStringStartsWith(sexp, "(function_definition type:");

    const new_tree = tree.dupe();
    defer new_tree.destroy();
    const edit: ts.InputEdit = .{
        .start_byte = 0,
        .start_point = .{ .row = 0, .column = 0 },
        .old_end_byte = 13,
        .new_end_byte = 9,
        .old_end_point = .{ .row = 0, .column = 13 },
        .new_end_point = .{ .row = 0, .column = 9 },
    };
    new_tree.edit(edit);
    node = new_tree.rootNode();
    node.edit(edit);

    try testing.expect(node.hasChanges());
    try testing.expect(!node.hasError());
}

test "Query" {
    const language = ts.Language.load("c");
    defer language.destroy();

    var error_offset: u32 = 0;
    try testing.expectError(error.InvalidNodeType, ts.Query.create(language, "(foo) @foo", &error_offset));
    try testing.expectEqual(1, error_offset);

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
        ;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    try testing.expectEqual(3, query.patternCount());
    try testing.expectEqual(3, query.captureCount());
    try testing.expectEqual(2, query.stringCount());

    try testing.expectEqual(23, query.startByteForPattern(1));
    try testing.expectEqual(54, query.endByteForPattern(1));

    try testing.expect(query.isPatternRooted(0));
    try testing.expect(!query.isPatternNonLocal(2));
    try testing.expect(!query.isPatternGuaranteedAtStep(9));

    try testing.expectEqualStrings("punctuation", query.captureNameForId(1).?);
    try testing.expectEqual(.One, query.captureQuantifierForId(0, 0).?);
    try testing.expectEqualStrings("main", query.stringValueForId(1).?);

    const steps: [4]ts.Query.PredicateStep = .{
        .{ .type = .String, .value_id = 0 },
        .{ .type = .Capture, .value_id = 2 },
        .{ .type = .String, .value_id = 1 },
        .{ .type = .Done, .value_id = 0 },
    };
    try testing.expectEqualSlices(ts.Query.PredicateStep, &steps, query.predicatesForPattern(2));
}

test "QueryCursor" {
    const language = ts.Language.load("c");
    defer language.destroy();

    const source =
        \\(identifier) @variable
        \\["{" "}" "(" ")"] @punctuation
        \\((identifier) @main
        \\ (#eq? @main "main"))
        ;
    var error_offset: u32 = 0;
    var query = try ts.Query.create(language, source, &error_offset);
    defer query.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language);

    const tree = try parser.parseBuffer("int main() {}", null, .UTF_8);
    defer tree.destroy();

    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();

    cursor.exec(query, tree.rootNode());

    try testing.expect(!cursor.didExceedMatchLimit());
    try testing.expectEqual(0xFFFFFFFF, cursor.getMatchLimit());
    try testing.expectEqual(0, cursor.getTimeoutMicros());

    var match = cursor.nextMatch().?;
    try testing.expectEqual(0, match.id);
    try testing.expectEqual(0, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(0, match.captures[0].index);
    try testing.expectEqualStrings("identifier", match.captures[0].node.@"type"());

    _ = cursor.nextMatch();

    match = cursor.nextCapture().?[1];
    try testing.expectEqual(2, match.id);
    try testing.expectEqual(1, match.pattern_index);
    try testing.expectEqual(1, match.captures.len);
    try testing.expectEqual(1, match.captures[0].index);
    try testing.expectEqualStrings("(", match.captures[0].node.@"type"());
}