#include <tree_sitter/api.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
const TSLanguage *tree_sitter_markdown_inline(void);
const TSLanguage *tree_sitter_markdown(void);
#ifdef OBSERVE_COMPARISON_WORK
extern uint64_t comparison_visit_count;
#define RESET_WORK() (comparison_visit_count = 0)
#define WORK_COUNT() comparison_visit_count
#else
#define RESET_WORK() ((void)0)
#define WORK_COUNT() UINT64_C(0)
#endif
static uint64_t mix(uint64_t h, uint64_t v) { return (h ^ v) * UINT64_C(1099511628211); }
static TSPoint point(const char *s, uint32_t at) {
 TSPoint p = {0,0}; for(uint32_t i=0;i<at;i++){if(s[i]=='\n'){p.row++;p.column=0;}else p.column++;}return p;
}
static uint64_t node_hash(TSNode node, uint64_t h) {
 const char *type=ts_node_type(node); for(;*type;type++)h=mix(h,(unsigned char)*type);
 h=mix(h,ts_node_start_byte(node)); h=mix(h,ts_node_end_byte(node));
 TSPoint a=ts_node_start_point(node),b=ts_node_end_point(node);h=mix(h,a.row);h=mix(h,a.column);h=mix(h,b.row);h=mix(h,b.column);
 h=mix(h,ts_node_is_missing(node));h=mix(h,ts_node_child_count(node));
 for(uint32_t i=0;i<ts_node_child_count(node);i++)h=node_hash(ts_node_child(node,i),h);return h;
}
static uint64_t digest(TSTree *tree, TSQuery *query) {
 uint64_t h=node_hash(ts_tree_root_node(tree),UINT64_C(1469598103934665603));TSQueryCursor *c=ts_query_cursor_new();TSQueryMatch m;
 ts_query_cursor_exec(c,query,ts_tree_root_node(tree));while(ts_query_cursor_next_match(c,&m)){h=mix(h,m.pattern_index);h=mix(h,m.capture_count);
 for(uint32_t i=0;i<m.capture_count;i++){h=mix(h,m.captures[i].index);h=node_hash(m.captures[i].node,h);}}
 ts_query_cursor_delete(c);return h;
}
static char *read_file(const char *name, uint32_t *count) {
 FILE *f=fopen(name,"rb");assert(f);assert(fseek(f,0,SEEK_END)==0);long size=ftell(f);assert(size>=0&&size<UINT32_MAX);rewind(f);
 char *p=malloc((size_t)size+1);assert(p);assert(fread(p,1,(size_t)size,f)==(size_t)size);fclose(f);p[size]=0;*count=(uint32_t)size;return p;
}
int main(int argc,char **argv){
 assert(argc==3);uint32_t length,qlength;char *source=read_file(argv[1],&length),*qtext=read_file(argv[2],&qlength);
 TSParser *parser=ts_parser_new();assert(ts_parser_set_language(parser,tree_sitter_markdown_inline()));uint32_t error;TSQueryError kind;
 TSQuery *query=ts_query_new(tree_sitter_markdown_inline(),qtext,qlength,&error,&kind);assert(query);free(qtext);
 TSRange *ranges=malloc(sizeof(TSRange)*(length/2+1));assert(ranges);uint32_t count=0;
 TSParser *blocks=ts_parser_new();assert(ts_parser_set_language(blocks,tree_sitter_markdown()));
 TSTree *block_tree=ts_parser_parse_string(blocks,NULL,source,length);assert(block_tree);
 const char *iq="(inline) @injection.content";TSQuery *injections=ts_query_new(tree_sitter_markdown(),iq,(uint32_t)strlen(iq),&error,&kind);assert(injections);
 TSQueryCursor *cursor=ts_query_cursor_new();TSQueryMatch match;ts_query_cursor_exec(cursor,injections,ts_tree_root_node(block_tree));
 while(ts_query_cursor_next_match(cursor,&match)){assert(match.capture_count==1);TSNode node=match.captures[0].node;
 ranges[count++]=(TSRange){.start_byte=ts_node_start_byte(node),.end_byte=ts_node_end_byte(node),.start_point=ts_node_start_point(node),.end_point=ts_node_end_point(node)};}
 ts_query_cursor_delete(cursor);ts_query_delete(injections);ts_tree_delete(block_tree);ts_parser_delete(blocks);assert(count>0);
 assert(ts_parser_set_included_ranges(parser,ranges,count));
 RESET_WORK();uint64_t begin=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);TSTree *tree=ts_parser_parse_string(parser,NULL,source,length);assert(tree);
 uint64_t elapsed=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-begin,work=WORK_COUNT();uint64_t initial=digest(tree,query);
 printf("phase=initial bytes=%u ranges=%u nodes=%llu ns=%llu digest=%016llx\n",length,count,(unsigned long long)work,(unsigned long long)elapsed,(unsigned long long)initial);
 TSRange target=ranges[count/2];uint32_t middle=target.start_byte+(target.end_byte-target.start_byte)/2;while(middle<target.end_byte&&!(source[middle]>='a'&&source[middle]<='z'))middle++;assert(middle<target.end_byte);
 TSInputEdit edit={.start_byte=middle,.old_end_byte=middle+1,.new_end_byte=middle+1,.start_point=point(source,middle),.old_end_point=point(source,middle+1),.new_end_point=point(source,middle+1)};
 source[middle]=source[middle]=='x'?'y':'x';ts_tree_edit(tree,&edit);
 RESET_WORK();begin=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);TSTree *edited=ts_parser_parse_string(parser,tree,source,length);assert(edited);
 elapsed=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-begin;work=WORK_COUNT();uint64_t actual=digest(edited,query);
 printf("phase=incremental bytes=%u ranges=%u nodes=%llu ns=%llu digest=%016llx\n",length,count,(unsigned long long)work,(unsigned long long)elapsed,(unsigned long long)actual);
 RESET_WORK();begin=clock_gettime_nsec_np(CLOCK_UPTIME_RAW);TSTree *fresh=ts_parser_parse_string(parser,NULL,source,length);assert(fresh);
 elapsed=clock_gettime_nsec_np(CLOCK_UPTIME_RAW)-begin;work=WORK_COUNT();uint64_t expected=digest(fresh,query);
 printf("phase=fresh bytes=%u ranges=%u nodes=%llu ns=%llu digest=%016llx\n",length,count,(unsigned long long)work,(unsigned long long)elapsed,(unsigned long long)expected);
 assert(actual==expected);ts_tree_delete(tree);ts_tree_delete(edited);ts_tree_delete(fresh);ts_parser_delete(parser);ts_query_delete(query);free(ranges);free(source);return 0;
}
