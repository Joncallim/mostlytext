import { build, version } from "./node_modules/esbuild/lib/main.js";
import { packageOptions } from "./.build/common.ts";
import { generateLangium } from "./.build/generateLangium.ts";
import { defaultOptions, getBuildConfig } from "./.esbuild/util.ts";
if (version !== '0.25.12') throw new Error('Unexpected compiler: ' + version);
await generateLangium();
const common = { ...defaultOptions, profiling: false, options: packageOptions.parser };
await Promise.all([common, {...common, minify: true, metafile: false}, {...common, core: true}].map(options => build(getBuildConfig(options))));
console.log(JSON.stringify({scope:'upstream parser build lane; no other packages/type prepack',esbuild:version,node:process.version,platform:process.platform,architecture:process.arch}));
