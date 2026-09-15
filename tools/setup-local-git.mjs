#!/usr/bin/env node
// 一次性本机配置：让签名配置永远不会被提交，且本地构建照常可用。
//
//   node tools/setup-local-git.mjs
//
// 做两件事：
//   1. 注册 Git clean filter（strip-signing）：提交前自动从 build-profile.json5
//      里去掉 signingConfigs / products[].signingConfig，工作区文件保持不动。
//      filter 标记为 required，过滤失败时提交直接报错，不会退化成「原样提交」。
//   2. 安装 pre-commit 钩子：提交前扫描暂存区，命中签名凭据或本机隐私信息就拦下。
//
// 这些配置只写在本仓库的 .git/ 下，不会进入版本库，也不影响其它工程。

import { execFileSync } from 'node:child_process';
import { writeFileSync, chmodSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const nodeExe = process.execPath.replace(/\\/g, '/');
const hookDir = resolve('.git', 'hooks');
const hookFile = resolve(hookDir, 'pre-commit');

if (!existsSync(hookDir)) {
  console.error('✗ 找不到 .git/hooks，请确认在仓库根目录运行本脚本。');
  process.exit(1);
}

// 定位 git：新装的 Git 可能还没进入当前终端的 PATH，这里逐个候选路径兜底
function resolveGit() {
  const candidates = [
    process.env.GIT,
    'git',
    'C:/Program Files/Git/cmd/git.exe',
    'C:/Program Files (x86)/Git/cmd/git.exe',
    'C:/Program Files/Git/bin/git.exe',
  ].filter(Boolean);

  for (const c of candidates) {
    try {
      execFileSync(c, ['--version'], { stdio: 'ignore' });
      return c;
    } catch {
      // 试下一个
    }
  }
  console.error('✗ 找不到 git 可执行文件。请安装 Git for Windows，或用 GIT 环境变量指定路径。');
  process.exit(1);
}

const GIT = resolveGit();

function git(...args) {
  execFileSync(GIT, args, { stdio: 'inherit' });
}

// 1) clean filter：提交时自动剥离签名配置
git('config', 'filter.strip-signing.clean', `"${nodeExe}" tools/strip-signing.mjs`);
git('config', 'filter.strip-signing.required', 'true');

// 2) pre-commit 钩子：兜底扫描，防止 filter 未生效时把隐私提交上去
const hook = [
  '#!/bin/sh',
  '# 由 tools/setup-local-git.mjs 生成：提交前扫描暂存区是否含签名凭据 / 本机隐私信息',
  `exec "${nodeExe}" tools/check-no-secrets.mjs`,
  '',
].join('\n');

writeFileSync(hookFile, hook, 'utf8');
try {
  chmodSync(hookFile, 0o755);
} catch {
  // Windows 上通常无实际作用，Git for Windows 会按 shebang 执行
}

console.log('✓ 已配置 clean filter  : filter.strip-signing.clean');
console.log('✓ 已启用 required       : 过滤失败时提交会报错而不是原样提交');
console.log('✓ 已安装 pre-commit 钩子: ' + hookFile.replace(/\\/g, '/'));
console.log('');
console.log('现在可以正常提交：build-profile.json5 里的签名配置会被自动剔除，');
console.log('工作区文件保持不变，本地构建照常可用。');
console.log('');
console.log('验证方式：');
console.log('  git add -A && git diff --cached -- build-profile.json5   # 看不到 signingConfigs 即成功');
