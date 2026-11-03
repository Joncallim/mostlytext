import webpack from 'webpack';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.dirname(fileURLToPath(import.meta.url));
for (const [name,target] of [['web','web'],['es5',['web','es5']]]) {
 await new Promise((resolve,reject)=>webpack({mode:'production',context:root,entry:'./entry.js',target,devtool:'source-map',optimization:{minimize:false},output:{path:path.join(root,'dist-'+name),filename:'reference.js',library:{type:'umd',name:'Fixture'},globalObject:'this'}},(error,stats)=>{
  if(error || stats.hasErrors()) reject(error || new Error(stats.toString({all:false,errors:true}))); else resolve();
 }));
}
console.log('Built reference with webpack '+webpack.version);
