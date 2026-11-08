#include <tree_sitter/api.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const TSLanguage *tree_sitter_markdown_inline(void);

enum { MAX_NODES = 512, MAX_DEPTH = 64 };

typedef struct {
    uint32_t depth, symbol, start, end, start_row, start_column, end_row, end_column;
    bool named, extra, missing, error;
} NodeFacts;

typedef struct {
    const char *name;
    const void *bytes;
    uint32_t length, start, narrow_end, expanded_end, row, unit;
} Fixture;

static void require(bool condition, const char *reason) {
    if (!condition) {
        fprintf(stderr, "Probe admission/API failure: %s\n", reason);
        exit(2);
    }
}

static void collect(TSNode node, uint32_t depth, NodeFacts *facts, size_t *count) {
    require(!ts_node_is_null(node) && depth < MAX_DEPTH && *count < MAX_NODES, "bounded valid tree");
    NodeFacts *row = &facts[(*count)++];
    memset(row, 0, sizeof(*row));
    TSPoint start = ts_node_start_point(node), end = ts_node_end_point(node);
    row->depth = depth;
    row->symbol = ts_node_symbol(node);
    row->start = ts_node_start_byte(node);
    row->end = ts_node_end_byte(node);
    row->start_row = start.row;
    row->start_column = start.column;
    row->end_row = end.row;
    row->end_column = end.column;
    row->named = ts_node_is_named(node);
    row->extra = ts_node_is_extra(node);
    row->missing = ts_node_is_missing(node);
    row->error = ts_node_is_error(node);
    uint32_t children = ts_node_child_count(node);
    for (uint32_t i = 0; i < children; i++) collect(ts_node_child(node, i), depth + 1, facts, count);
}

static bool same_tree(TSTree *left, TSTree *right) {
    NodeFacts a[MAX_NODES], b[MAX_NODES];
    size_t a_count = 0, b_count = 0;
    collect(ts_tree_root_node(left), 0, a, &a_count);
    collect(ts_tree_root_node(right), 0, b, &b_count);
    return a_count == b_count && memcmp(a, b, a_count * sizeof(*a)) == 0;
}

static uint32_t code_spans(TSNode node) {
    uint32_t result = strcmp(ts_node_type(node), "code_span") == 0;
    for (uint32_t i = 0; i < ts_node_child_count(node); i++) result += code_spans(ts_node_child(node, i));
    return result;
}

static void set_range(TSParser *parser, const Fixture *fixture, uint32_t end) {
    TSRange range = {
        .start_byte = fixture->start,
        .end_byte = end,
        .start_point = {.row = fixture->row, .column = 0},
        .end_point = {.row = fixture->row, .column = end - fixture->start},
    };
    require(ts_parser_set_included_ranges(parser, &range, 1), "included range admitted");
}

static TSParser *new_parser(void) {
    TSParser *parser = ts_parser_new();
    require(parser != NULL, "parser allocation");
    require(ts_parser_set_language(parser, tree_sitter_markdown_inline()), "exact inline grammar ABI");
    return parser;
}

static TSTree *parse(TSParser *parser, const TSTree *old, const Fixture *fixture, const char *phase) {
    TSInputEncoding encoding = fixture->unit == 1 ? TSInputEncodingUTF8 : TSInputEncodingUTF16LE;
    TSTree *tree = ts_parser_parse_string_encoding(parser, old, fixture->bytes, fixture->length, encoding);
    if (tree) {
        char *actual = ts_node_string(ts_tree_root_node(tree));
        require(actual != NULL && strlen(actual) < 8192, "bounded actual diagnostic tree");
        fprintf(stderr, "PHASE fixture=%s phase=%s has_error=%u tree=%s\n", fixture->name, phase,
                ts_node_has_error(ts_tree_root_node(tree)), actual);
        free(actual);
    } else {
        fprintf(stderr, "PHASE fixture=%s phase=%s tree=NULL\n", fixture->name, phase);
    }
    require(tree != NULL, "complete returned parse tree");
    return tree;
}

static void print_tree(TSTree *tree) {
    NodeFacts rows[MAX_NODES];
    size_t count = 0;
    collect(ts_tree_root_node(tree), 0, rows, &count);
    printf("[");
    for (size_t i = 0; i < count; i++) {
        NodeFacts *r = &rows[i];
        if (i) printf(",");
        printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]", r->depth, r->symbol, r->start, r->end,
               r->start_row, r->start_column, r->end_row, r->end_column,
               r->named, r->extra, r->missing, r->error);
    }
    printf("]");
}

static unsigned exercise(const Fixture *fixture) {
    TSParser *parser = new_parser(), *fresh_parser = new_parser();
    set_range(parser, fixture, fixture->narrow_end);
    TSTree *initial = parse(parser, NULL, fixture, "initial");
    require(!ts_node_has_error(ts_tree_root_node(initial)), "fresh narrow reference is error-free");
    TSTree *unchanged = parse(parser, initial, fixture, "unchanged");
    bool unchanged_equal = same_tree(initial, unchanged);
    set_range(parser, fixture, fixture->expanded_end);
    TSTree *expanded = parse(parser, initial, fixture, "expanded");
    set_range(fresh_parser, fixture, fixture->expanded_end);
    TSTree *fresh = parse(fresh_parser, NULL, fixture, "fresh");
    require(!ts_node_has_error(ts_tree_root_node(fresh)), "fresh full reference is error-free");
    uint32_t expected_spans = code_spans(ts_tree_root_node(fresh));
    require(expected_spans == 1 && code_spans(ts_tree_root_node(initial)) == 0, "actual code-span positive and narrow negative");
    bool expanded_equal = same_tree(expanded, fresh);
    set_range(parser, fixture, fixture->narrow_end);
    TSTree *shrunk = parse(parser, fresh, fixture, "shrunk");
    bool shrunk_equal = same_tree(shrunk, initial);
    printf("{\"name\":\"%s\",\"source_hex\":\"", fixture->name);
    const unsigned char *bytes = fixture->bytes;
    for (uint32_t i = 0; i < fixture->length; i++) printf("%02x", bytes[i]);
    printf("\",\"unit_bytes\":%u,\"range\":[%u,%u,%u],\"unchanged_equal\":%s,\"expanded_equal\":%s,\"shrunk_equal\":%s,",
           fixture->unit, fixture->start, fixture->narrow_end, fixture->expanded_end,
           unchanged_equal ? "true" : "false", expanded_equal ? "true" : "false", shrunk_equal ? "true" : "false");
    printf("\"expanded_code_spans\":%u,\"fresh_code_spans\":%u,\"trees\":{\"initial\":", code_spans(ts_tree_root_node(expanded)), expected_spans);
    print_tree(initial);
    printf(",\"unchanged\":"); print_tree(unchanged);
    printf(",\"expanded\":"); print_tree(expanded);
    printf(",\"fresh\":"); print_tree(fresh);
    printf(",\"shrunk\":"); print_tree(shrunk);
    printf("}}");
    unsigned failures = !unchanged_equal + !expanded_equal + !shrunk_equal;
    ts_tree_delete(shrunk); ts_tree_delete(fresh); ts_tree_delete(expanded);
    ts_tree_delete(unchanged); ts_tree_delete(initial);
    ts_parser_delete(fresh_parser); ts_parser_delete(parser);
    return failures;
}

int main(int argc, char **argv) {
    (void)argv;
    require(argc == 1, "fixed generated fixtures only");
    const uint16_t little_endian = 1;
    require(*(const unsigned char *)&little_endian == 1, "UTF-16 little-endian memory representation");
    static const char plain8[] = "`c `";
    static const uint16_t plain16[] = {'`', 'c', ' ', '`'};
    static const char prefix8[] = "\xc3\xa9\n`c `";
    static const uint16_t prefix16[] = {0xe9, '\n', '`', 'c', ' ', '`'};
    static const char emoji8[] = "`\xf0\x9f\x98\x80 `";
    static const uint16_t emoji16[] = {'`', 0xd83d, 0xde00, ' ', '`'};
    static const char combining8[] = "`e\xcc\x81 `";
    static const uint16_t combining16[] = {'`', 'e', 0x301, ' ', '`'};
    const Fixture fixtures[] = {
        {"utf8", plain8, 4, 0, 2, 4, 0, 1},
        {"utf16le", plain16, 8, 0, 4, 8, 0, 2},
        {"utf8-prefix", prefix8, 7, 3, 5, 7, 1, 1},
        {"utf16le-prefix", prefix16, 12, 4, 8, 12, 1, 2},
        {"utf8-emoji", emoji8, 7, 0, 5, 7, 0, 1},
        {"utf16le-emoji", emoji16, 10, 0, 6, 10, 0, 2},
        {"utf8-combining", combining8, 6, 0, 4, 6, 0, 1},
        {"utf16le-combining", combining16, 10, 0, 6, 10, 0, 2},
    };
    unsigned failures = 0;
    printf("{\"scope\":\"actual current C runtime and vendored inline grammar only; no native product/performance claim\",\"cases\":[");
    for (size_t i = 0; i < sizeof(fixtures) / sizeof(*fixtures); i++) {
        if (i) printf(",");
        failures += exercise(&fixtures[i]);
    }
    printf("],\"semantic_failures\":%u}\n", failures);
    return failures ? 65 : 0;
}
