// Actual Markdown-inline parser/query differential control, UTF-8/UTF-16 LE/BE.
// Independent all-step behavior trace. Fresh-tree mismatches are counted and
// KEEP a nonzero exit status; compare all 6,000 old/new-runtime traces as well.
// The original fail-fast fresh oracle remains unchanged in valid_scalar_edits.c.
#include <tree_sitter/api.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const TSLanguage *tree_sitter_markdown_inline(void);
enum { SEGMENTS = 12, CAPACITY = 128, ITERATIONS = 2000 };
static uint16_t body[SEGMENTS][CAPACITY];
static uint32_t lengths[SEGMENTS], seed;
static uint32_t random_number(void) { seed = seed * 1664525u + 1013904223u; return seed; }
static uint64_t mix(uint64_t hash, uint64_t value) { return (hash ^ value) * UINT64_C(1099511628211); }
static uint64_t node_hash(TSNode node, uint64_t hash) {
  const char *type = ts_node_type(node);
  for (; *type; type++) hash = mix(hash, (unsigned char)*type);
  hash = mix(hash, ts_node_start_byte(node)); hash = mix(hash, ts_node_end_byte(node));
  TSPoint start = ts_node_start_point(node), end = ts_node_end_point(node);
  hash = mix(hash, start.row); hash = mix(hash, start.column);
  hash = mix(hash, end.row); hash = mix(hash, end.column);
  hash = mix(hash, ts_node_is_missing(node)); hash = mix(hash, ts_node_child_count(node));
  for (uint32_t i = 0; i < ts_node_child_count(node); i++) hash = node_hash(ts_node_child(node, i), hash);
  return hash;
}
static uint64_t tree_hash(TSTree *tree, TSQuery *query) {
  uint64_t hash = node_hash(ts_tree_root_node(tree), UINT64_C(1469598103934665603));
  TSQueryCursor *cursor = ts_query_cursor_new(); TSQueryMatch match;
  ts_query_cursor_exec(cursor, query, ts_tree_root_node(tree));
  while (ts_query_cursor_next_match(cursor, &match)) {
    hash = mix(hash, match.pattern_index); hash = mix(hash, match.capture_count);
    for (uint32_t i = 0; i < match.capture_count; i++) {
      hash = mix(hash, match.captures[i].index);
      hash = node_hash(match.captures[i].node, hash);
    }
  }
  ts_query_cursor_delete(cursor); return hash;
}
static TSPoint point_at(const unsigned char *text, uint32_t offset, unsigned mode) {
  TSPoint point = {0, 0}; unsigned width = mode ? 2 : 1;
  for (uint32_t i = 0; i < offset; i += width) {
    uint16_t unit = !mode ? text[i] : mode == 1 ? text[i] | (text[i+1] << 8) : (text[i] << 8) | text[i+1];
    if (unit == '\n') { point.row++; point.column = 0; } else point.column += width;
  }
  return point;
}
static uint32_t encode(unsigned mode, unsigned char *text, TSRange *ranges) {
  unsigned width = mode ? 2 : 1; uint32_t position = 0;
  for (uint32_t i = 0; i < SEGMENTS; i++) {
    ranges[i].start_byte = position; ranges[i].start_point = point_at(text, position, mode);
    for (uint32_t j = 0; j <= lengths[i]; j++) {
      uint16_t unit = j == lengths[i] ? '\n' : body[i][j];
      if (!mode) text[position++] = (unsigned char)unit;
      else if (mode == 1) { text[position++] = unit & 255; text[position++] = unit >> 8; }
      else { text[position++] = unit >> 8; text[position++] = unit & 255; }
      if (j + 1 == lengths[i]) { ranges[i].end_byte = position; ranges[i].end_point = point_at(text, position, mode); }
    }
    if (!lengths[i]) { ranges[i].end_byte = ranges[i].start_byte; ranges[i].end_point = ranges[i].start_point; }
  }
  (void)width; return position;
}
static uint32_t scalar_start(unsigned mode, uint32_t segment, uint32_t at) {
  if (at == lengths[segment]) return at;
  if (!mode) { while (at && (body[segment][at] & 0xc0) == 0x80) at--; }
  else if (at && body[segment][at] >= 0xdc00 && body[segment][at] <= 0xdfff) at--;
  return at;
}
static uint32_t scalar_count(unsigned mode, uint32_t segment, uint32_t at) {
  if (at == lengths[segment]) return 0;
  uint16_t first = body[segment][at];
  uint32_t count = mode ? (first >= 0xd800 && first <= 0xdbff ? 2 : 1) :
    first < 0x80 ? 1 : first < 0xe0 ? 2 : first < 0xf0 ? 3 : 4;
  assert(at + count <= lengths[segment]); return count;
}
static uint32_t scalar_units(unsigned mode, uint32_t scalar, uint16_t *out) {
  if (mode) {
    if (scalar <= 0xffff) { out[0] = (uint16_t)scalar; return 1; }
    scalar -= 0x10000; out[0] = 0xd800 + (scalar >> 10); out[1] = 0xdc00 + (scalar & 0x3ff); return 2;
  }
  if (scalar < 0x80) { out[0] = scalar; return 1; }
  if (scalar < 0x800) { out[0] = 0xc0 | (scalar >> 6); out[1] = 0x80 | (scalar & 63); return 2; }
  if (scalar < 0x10000) { out[0] = 0xe0 | (scalar >> 12); out[1] = 0x80 | ((scalar >> 6) & 63); out[2] = 0x80 | (scalar & 63); return 3; }
  out[0] = 0xf0 | (scalar >> 18); out[1] = 0x80 | ((scalar >> 12) & 63); out[2] = 0x80 | ((scalar >> 6) & 63); out[3] = 0x80 | (scalar & 63); return 4;
}
int main(int argc, char **argv) {
  assert(argc == 2); FILE *file = fopen(argv[1], "rb");
  if (!file) { perror(argv[1]); return 64; }
  assert(fseek(file, 0, SEEK_END) == 0); long query_length = ftell(file); rewind(file);
  char *query_text = malloc((size_t)query_length); assert(query_text);
  assert(fread(query_text, 1, (size_t)query_length, file) == (size_t)query_length); fclose(file);
  uint32_t error_offset = 0; TSQueryError error_type;
  TSQuery *query = ts_query_new(tree_sitter_markdown_inline(), query_text, (uint32_t)query_length, &error_offset, &error_type);
  assert(query); free(query_text);
  static const uint16_t pattern[] = {'*','c','a','f',0xe9,' ',0x4e2d,' ',0xd83d,0xde03,' ','*','*','b','o','l','d','*','*',' ','`','c','o','d','e','`','*'};
  static const uint32_t additions[] = {'a','*','`','[',']','\n','\r',0xe9,0x4e2d,0x1f603};
  unsigned divergences = 0;
  for (unsigned mode = 0; mode < 3; mode++) {
    seed = 0x2468ace0;
    static const unsigned char pattern8[] = "*caf\xc3\xa9 \xe4\xb8\xad \xf0\x9f\x98\x83 **bold** `code`*";
    for (uint32_t i = 0; i < SEGMENTS; i++) {
      if (!mode) {
        lengths[i] = sizeof(pattern8) - 1;
        for (uint32_t j = 0; j < lengths[i]; j++) body[i][j] = pattern8[j];
      } else { lengths[i] = sizeof(pattern)/sizeof(pattern[0]); memcpy(body[i], pattern, sizeof(pattern)); }
    }
    unsigned width = mode ? 2 : 1;
    unsigned char text[SEGMENTS * (CAPACITY + 1) * 2]; TSRange ranges[SEGMENTS];
    TSInputEncoding encoding = !mode ? TSInputEncodingUTF8 : mode == 1 ? TSInputEncodingUTF16LE : TSInputEncodingUTF16BE;
    TSParser *edited_parser = ts_parser_new(), *fresh_parser = ts_parser_new();
    assert(ts_parser_set_language(edited_parser, tree_sitter_markdown_inline()));
    assert(ts_parser_set_language(fresh_parser, tree_sitter_markdown_inline()));
    uint32_t length = encode(mode, text, ranges); assert(ts_parser_set_included_ranges(edited_parser, ranges, SEGMENTS));
    TSTree *tree = ts_parser_parse_string_encoding(edited_parser, NULL, (char *)text, length, encoding); assert(tree);
    uint64_t digest = UINT64_C(1469598103934665603);
    for (uint32_t iteration = 0; iteration < ITERATIONS; iteration++) {
      uint32_t segment = random_number() % SEGMENTS, at = random_number() % (lengths[segment] + 1);
      at = scalar_start(mode, segment, at);
      unsigned operation = random_number() % 3;
      uint32_t remove = operation != 0 ? scalar_count(mode, segment, at) : 0;
      uint16_t insertion[4];
      uint32_t insert = operation != 1 || !lengths[segment] ? scalar_units(mode, additions[random_number() % (sizeof(additions)/sizeof(additions[0]))], insertion) : 0;
      if (lengths[segment] + insert - remove > CAPACITY) {
        insert = 0;
        if (!remove) { at = scalar_start(mode, segment, lengths[segment] - 1); remove = scalar_count(mode, segment, at); }
      }
      uint32_t start = ranges[segment].start_byte + at * width;
      TSInputEdit edit = {.start_byte = start, .old_end_byte = start + remove * width, .new_end_byte = start + insert * width,
        .start_point = point_at(text, start, mode), .old_end_point = point_at(text, start + remove * width, mode)};
      memmove(body[segment] + at + insert, body[segment] + at + remove, (lengths[segment] - at - remove) * sizeof(uint16_t));
      if (insert) memcpy(body[segment] + at, insertion, insert * sizeof(uint16_t));
      lengths[segment] = lengths[segment] + insert - remove;
      length = encode(mode, text, ranges); edit.new_end_point = point_at(text, edit.new_end_byte, mode);
      ts_tree_edit(tree, &edit);
      assert(ts_parser_set_included_ranges(edited_parser, ranges, SEGMENTS));
      assert(ts_parser_set_included_ranges(fresh_parser, ranges, SEGMENTS));
      TSTree *next = ts_parser_parse_string_encoding(edited_parser, tree, (char *)text, length, encoding);
      TSTree *fresh = ts_parser_parse_string_encoding(fresh_parser, NULL, (char *)text, length, encoding); assert(next && fresh);
      uint64_t actual = tree_hash(next, query), expected = tree_hash(fresh, query);
      printf("trace mode=%u edit=%u actual=%016llx fresh=%016llx\n", mode, iteration, (unsigned long long)actual, (unsigned long long)expected);
      if (actual != expected) {
        divergences++;
        fprintf(stderr, "fresh-divergence mode=%u iteration=%u actual=%016llx fresh=%016llx\n", mode, iteration, (unsigned long long)actual, (unsigned long long)expected);
      }
      digest = mix(digest, actual); ts_tree_delete(tree); ts_tree_delete(fresh); tree = next;
    }
    printf("mode=%u edits=%u tree-and-query-digest=%016llx\n", mode, ITERATIONS, (unsigned long long)digest);
    ts_tree_delete(tree); ts_parser_delete(edited_parser); ts_parser_delete(fresh_parser);
  }
  ts_query_delete(query); fprintf(stderr, "fresh-divergences=%u; nonzero status retained\n", divergences); return divergences ? 2 : 0;
}
