#!/usr/bin/env node
// Git clean filter：把工程级 build-profile.json5 中的签名配置（signingConfigs 与
// products[].signingConfig）剥离后再写入 Git 对象库。
//
// 效果：本地文件里的签名信息（含本机绝对路径与签名口令）永远不会被提交，
//       而本地构建依然可用 —— 不需要每次提交前手动删签名配置。
//
// 安装：node tools/setup-local-git.mjs
// 用法：由 .gitattributes 的 `build-profile.json5 filter=strip-signing` 自动调用，
//       也可手动验证：node tools/strip-signing.mjs < build-profile.json5
//
// 注意：只做行级处理，不重新序列化 JSON5，以保留原有注释与格式。

import { readFileSync } from 'node:fs';

const MARKER = [
  '    // 签名配置（signingConfigs）不入库：由各开发者在本机 DevEco Studio 中生成，',
  '    // 避免把本机绝对路径与签名口令提交到公开仓库。',
  '    // 首次构建：File → Project Structure → Signing Configs → 勾选 "Automatically generate signature"，',
  '    // IDE 会把 signingConfigs 写回本文件（写回的内容不会进入版本库，见 README「签名配置为什么不入库」）。',
];

const input = readFileSync(0, 'utf8');
const lines = input.split(/\r?\n/);

// 第一遍：判断是否存在签名配置，决定要不要补说明注释
const hasSigning = lines.some(
  (l) => /^\s*"signingConfigs"\s*:/.test(l) || /^\s*"signingConfig"\s*:/.test(l)
);

// 第二遍：剥离签名配置
const out = [];
let skipping = false;
let depth = 0;
let commentEmitted = false;

for (const line of lines) {
  if (skipping) {
    depth += count(line, '[') - count(line, ']');
    if (depth <= 0) {
      skipping = false;
    }
    continue;
  }
  if (/^\s*"signingConfigs"\s*:\s*\[/.test(line)) {
    skipping = true;
    depth = count(line, '[') - count(line, ']');
    if (depth <= 0) {
      skipping = false;
    }
    continue;
  }
  if (/^\s*"signingConfig"\s*:/.test(line)) {
    continue;
  }

  out.push(line);
  if (hasSigning && !commentEmitted && /"app"\s*:\s*\{/.test(line)) {
    out.push(...MARKER);
    commentEmitted = true;
  }
}

let result = out.join('\n');
if (!result.endsWith('\n')) {
  result += '\n';
}
process.stdout.write(result);

function count(s, ch) {
  let n = 0;
  for (const c of s) {
    if (c === ch) {
      n++;
    }
  }
  return n;
}
