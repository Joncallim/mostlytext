// Audit-only: no product execution and no inferred copyright disposition.
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const sha = b => createHash('sha256').update(b).digest('hex');
const INDEX_SHA = '4137239965a49864f71dc3ecbce8dfc04833731c0e92a55cd2dd44b6a9958ec3';
const PARENT_SHA = 'de87447fd7390841f770969dcc9ed44a243f098546086f5cd40cfa3ca0fae63f';
const ACORN_SHA = '76254fc76529713b4dfd2532972d17a991ffd9aafeebb1f977445b5506b9fb0b';
const [acornPath,indexPath,parentPath,membersPath,outputPath] = process.argv.slice(2);
assert.equal(process.version,'v24.16.0');
assert.equal(sha(readFileSync(acornPath)),ACORN_SHA,'Audit parser identity');
const {parse,version} = await import(pathToFileURL(path.resolve(acornPath)).href);
assert.equal(version,'8.19.0');

function inspect(code) {
  const tokens=[],nodes=[],parents=new Map(),stack=[];
  const tree=parse(code,{ecmaVersion:2025,sourceType:'module',locations:true,onToken:tokens});
  stack.push(tree);
  while(stack.length) {
    const node=stack.pop(); nodes.push(node);
    for(const value of Object.values(node)) {
      const children=Array.isArray(value)?value:[value];
      for(const child of children) if(child && typeof child.type==='string') {
        parents.set(child,node);stack.push(child);
      }
    }
  }
  const starts=[0],lines=code.split('\n');
  for(let i=0;i<code.length;i++)if(code[i]==='\n')starts.push(i+1);
  const contains=(node,offset)=>node.start<=offset&&offset<node.end;
  const iife=arrow=>arrow?.type==='ArrowFunctionExpression' && !arrow.async && arrow.params.length===0
    && arrow.body.type==='BlockStatement' && parents.get(arrow)?.type==='CallExpression'
    && parents.get(arrow).callee===arrow && parents.get(arrow).arguments.length===0
    && parents.get(parents.get(arrow))?.type==='ExpressionStatement'
    && parents.get(parents.get(parents.get(arrow)))?.type==='Program';
  return (line,column)=>{
    assert(Number.isInteger(line)&&Number.isInteger(column)&&line>0&&column>0);
    assert(line<=lines.length&&column<=lines[line-1].length+1,'UTF-16 coordinate bounds');
    const offset=starts[line-1]+column-1;
    const token=tokens.find(t=>contains(t,offset));
    if(!token)return {category:'unclassified'};
    const label=token.type.label;
    const chain=nodes.filter(n=>contains(n,offset)).sort((a,b)=>(a.end-a.start)-(b.end-b.start));
    let category='unclassified',support;
    for(const node of chain) {
      const parent=parents.get(node);
      if(node.type==='CallExpression' && node.callee.type==='Super' && node.arguments.length===1
          && node.arguments[0].type==='SpreadElement' && node.arguments[0].argument.type==='Identifier'
          && node.arguments[0].argument.name==='arguments' && parent?.type==='ExpressionStatement') {
        const block=parents.get(parent),fn=parents.get(block),method=parents.get(fn);
        if(block?.type==='BlockStatement' && fn?.type==='FunctionExpression' && fn.body===block
            && method?.type==='MethodDefinition' && method.kind==='constructor'
            && method.value===fn && fn.params.length===0)category='constructor-super-forwarding';
      }
      if(node.type==='VariableDeclaration' && node.kind==='var'
          && node.declarations.every(d=>d.id.type==='Identifier'&&d.init===null))category='uninitialized-var-declaration';
      if((node.type==='ObjectExpression' && label==='}') || (node.type==='ArrayExpression' && label===']')) {
        if(token.end===node.end)category=node.type==='ObjectExpression'?'closing-object-delimiter':'closing-array-delimiter';
      }
      if(node.type==='IfStatement' && label==='if' && token.start===node.start
          && parent?.type==='IfStatement' && parent.alternate===node)category='else-if-keyword';
      if(node.type==='BlockStatement' && label==='}' && token.end===node.end
          && parent?.type==='IfStatement' && parent.consequent===node && parent.alternate!==null)category='alternate-block-boundary';
      if(iife(node) && token.end<=node.body.start+1)category='invoked-arrow-header';
      if(node.type==='ExpressionStatement' && node.directive==='use strict'
          && parent?.type==='BlockStatement' && iife(parents.get(parent)))category='wrapper-strict-directive';
      if(node.type==='StaticBlock' && label==='name' && token.value==='static'
          && token.start===node.start && parent?.type==='ClassBody')category='static-block-opening';
      if(node.type==='VariableDeclaration' && node.kind==='var' && node.declarations.length>0
          && node.declarations[0].id.type==='Identifier' && parent?.type==='BlockStatement'
          && iife(parents.get(parent))) {
        const table=node.declarations[0].init;
        if(table?.type==='ObjectExpression' && table.properties.length>0
            && table.properties.every(p=>p.type==='Property' && p.kind==='init' && !p.computed && !p.method
              && p.key.type==='Literal' && Number.isSafeInteger(p.key.value) && p.key.value>=0
              && p.value.type==='ArrowFunctionExpression' && !p.value.async
              && p.value.params.length>0 && p.value.params.length<=3
              && p.value.params.every(n=>n.type==='Identifier') && p.value.body.type==='BlockStatement')
            && token.end<=table.properties[0].value.body.start+1)category='numeric-module-table-header';
      }
      if(category!=='unclassified'){support=node;break;}
    }
    if(!support)return {category};
    return {category,token_type:label,token_span:[token.start,token.end],token_sha256:sha(code.slice(token.start,token.end)),
      node_type:support.type,node_span:[support.start,support.end],node_sha256:sha(code.slice(support.start,support.end))};
  };
}

const controls=[
  ['class C extends B { constructor(){ super(...arguments); } }','super', 'constructor-super-forwarding'],
  ['class C extends B { constructor(){ super(changed); } }','super','unclassified'],
  ['class C extends B { constructor(x){ super(...arguments); } }','super','unclassified'],
  ['class C extends B { constructor(){ (()=>{super(...arguments);})(); } }','super','unclassified'],
  ['var _a, _b;','_a','uninitialized-var-declaration'],
  ['var _a = sideEffect();','_a','unclassified'],
  ['const x = ({p:1}).p;','}', 'closing-object-delimiter'],
  ['const x = [1].concat(y);',']','closing-array-delimiter'],
  ['const x = `\n});\n`;','}','unclassified'],
  ['/* else if } */','}','unclassified'],
  ['if(x){} else if(y){}','if(y)','else-if-keyword'],
  ['if(x){} else {}','}', 'alternate-block-boundary'],
  ['const x = "else if";','if','unclassified'],
  ['(() => { sideEffect(); })();','() =>','invoked-arrow-header'],
  ['(() => { sideEffect(); })();','(','unclassified'],
  ['(x => { sideEffect(); })(1);','(','unclassified'],
  ['function f(){ (() => { sideEffect(); })(); }','() =>','unclassified'],
  ['(() => { "use strict"; })();','"use strict"','wrapper-strict-directive'],
  ['(() => { "not strict"; })();','"not strict"','unclassified'],
  ['(() => { var t={975:(m)=>{ sideEffect(); }}; })();','975','numeric-module-table-header'],
  ['(() => { var t={975:(m)=>{ sideEffect(); }}; })();','sideEffect','unclassified'],
  ['(() => { var t={975:(m)=>{}}, cache={}; })();','975','numeric-module-table-header'],
  ['(() => { var t={975:(m)=>{}}, cache={}; })();','cache','unclassified'],
  ['(() => { var t={name:(m)=>{}}; })();','name','unclassified'],
  ['class C { static { __name(this,"C"); } }','static','static-block-opening'],
  ['const x = "static {";','static','unclassified'],
  ['const emoji="😀"; var _a;','_a','uninitialized-var-declaration'],
];
for(const [code,probe,wanted] of controls) {
  const offset=code.indexOf(probe);assert(offset>=0);
  const before=code.slice(0,offset).split('\n');
  assert.equal(inspect(code)(before.length,before.at(-1).length+1).category,wanted,code);
}
const rawIndex=readFileSync(indexPath),rawParent=readFileSync(parentPath);
assert.equal(sha(rawIndex),INDEX_SHA,'Original index identity');
assert.equal(sha(rawParent),PARENT_SHA,'Parent classification identity');
const index=JSON.parse(rawIndex),parent=JSON.parse(rawParent),cache=new Map(),categories={},positions=[];
for(const old of parent.positions.filter(r=>r.technical_category==='unclassified')) {
  const row=index.positions[old.original_row_index];
  const canonical=Object.fromEntries(Object.keys(row).sort().map(k=>[k,row[k]]));
  assert.equal(sha(JSON.stringify(canonical)),old.original_row_sha256,'Original row identity');
  assert(row.parser_member.startsWith('dist/')&&!row.parser_member.split('/').includes('..'));
  if(!cache.has(row.parser_member)) {
    const raw=readFileSync(path.join(membersPath,row.parser_member));
    assert.equal(sha(raw),row.parser_member_sha256,'Reproduced member identity');
    cache.set(row.parser_member,inspect(raw.toString('utf8')));
  }
  const result=cache.get(row.parser_member)(row.parser_line,row.parser_utf16_column);
  categories[result.category]=(categories[result.category]||0)+row.outer_reference_count;
  positions.push({...old,...result});
}
if(categories.unclassified) console.error(JSON.stringify({unclassified_rows:positions.filter(p=>p.category==='unclassified').map(p=>p.original_row_index),categories}));
assert.equal(positions.length,100);assert.equal(categories.unclassified||0,0,'Residual positions still need inspection');
const receipt={schema:1,scope:'Residual syntax disposition only; all original independent attribution/rights review requirements remain',
  original_index_sha256:INDEX_SHA,parent_classification_sha256:PARENT_SHA,parser_module_sha256:ACORN_SHA,
  node:process.version,parser:'acorn@8.19.0',parser_controls:controls.length,independent_review_required:true,
  reviewed_references:100,remaining_technically_unclassified:0,categories,positions};
writeFileSync(outputPath,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify({positions:positions.length,categories,parserControls:controls.length}));
