#!/usr/bin/env node
// 提交前隐私扫描：检查「暂存区」内容里是否混入了签名凭据或本机隐私信息。
//
// 由 .git/hooks/pre-commit 自动调用（安装见 tools/setup-local-git.mjs），
// 也可手动运行：
//   node tools/check-no-secrets.mjs          # 只扫描暂存区（默认，用于 pre-commit）
//   node tools/check-no-secrets.mjs --all    # 扫描全部已被 Git 跟踪的文件
//
// 命中任意一条即返回非 0，提交会被中断。

import { execFileSync } from 'node:child_process';

const RULES = [
  { id: 'signing-material', re: /"(keyPassword|storePassword|certpath|storeFile|profile|signAlg)"\s*:/i,
    why: '签名材料字段（含本机证书路径与签名口令）' },
  { id: 'private-key', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    why: '私钥文件内容' },
  { id: 'ohos-config-path', re: /\.ohos[\\/]config[\\/]/i,
    why: 'HarmonyOS 本机证书目录下的实际路径' },
  { id: 'windows-user-path', re: /[A-Za-z]:\\+Users\\+[^\\\s"'<]+/i,
    why: '本机 Windows 用户目录绝对路径（含用户名）' },
  { id: 'lan-ip', re: /\b(192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/,
    why: '局域网 IP（无线调试等本机网络信息）' },
];

const scanAll = process.argv.includes('--all');

// 本脚本自身与安装脚本里含有这些规则/路径的字面量，跳过以免自报
const SELF = ['tools/check-no-secrets.mjs', 'tools/setup-local-git.mjs'];

// 误报豁免：在行尾加 privacy-check:allow 即跳过该行（例如文档里举例说明规则本身时）
const ALLOW = /privacy-check:allow/;

// 定位 git：新装的 Git 可能还没进入当前终端的 PATH，这里逐个候选路径兜底
// （由 Git 触发的 pre-commit 钩子里 PATH 已由 Git 注入，这个兜底主要给手动运行用）
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

function listFiles() {
  // 用 -z：路径以 NUL 分隔且不做转义，避免中文文件名被 Git 加上引号与八进制转义
  const args = scanAll
    ? ['ls-files', '-z']
    : ['diff', '--cached', '--name-only', '-z', '--diff-filter=ACM'];
  return execFileSync(GIT, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
    .split('\u0000')
    .map((s) => s.trim())
    .filter(Boolean);
}

function stagedContent(path) {
  // 取「暂存区里的版本」，而不是工作区版本 —— 这才是真正会被提交的内容
  const args = scanAll ? ['show', `HEAD:${path}`] : ['show', `:${path}`];
  try {
    return execFileSync(GIT, args, {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'], // 默认会把 git 的 stderr 直接继承到终端，这里收起来
    });
  } catch {
    return null;
  }
}

const findings = [];
for (const file of listFiles()) {
  if (SELF.includes(file.replace(/\\/g, '/'))) {
    continue;
  }
  const text = stagedContent(file);
  if (text === null || text.includes('\u0000')) {
    continue; // 二进制或不可读
  }
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (ALLOW.test(lines[i])) {
      continue;
    }
    for (const rule of RULES) {
      if (rule.re.test(lines[i])) {
        findings.push({ file, line: i + 1, id: rule.id, why: rule.why });
        break;
      }
    }
  }
}

if (findings.length === 0) {
  console.log('[privacy-check] OK：暂存内容未发现签名凭据或本机隐私信息。');
  process.exit(0);
}

console.error('\n[privacy-check] ✗ 阻止提交：发现 ' + findings.length + ' 处敏感内容\n');
const byFile = new Map();
for (const f of findings) {
  if (!byFile.has(f.file)) {
    byFile.set(f.file, []);
  }
  byFile.get(f.file).push(f);
}
for (const [file, list] of byFile) {
  console.error('  ' + file);
  for (const f of list.slice(0, 5)) {
    console.error('    第 ' + f.line + ' 行  →  ' + f.why);
  }
  if (list.length > 5) {
    console.error('    …（另有 ' + (list.length - 5) + ' 处）');
  }
}
console.error('\n处理办法：');
console.error('  1. build-profile.json5 里的签名配置本应由 clean filter 自动剥离；');
console.error('     若这里报出来，说明 filter 没装：运行  node tools/setup-local-git.mjs');
console.error('  2. 文档/注释里的本机路径请改为 <工程根目录>、<用户名> 之类的占位写法。');
console.error('  3. 确属误报（如文档在举例说明规则本身）时，在该行行尾加  privacy-check:allow  标记。');
console.error('  4. 仍要强行提交可用  git commit --no-verify  临时跳过（请谨慎）。\n');
process.exit(1);
