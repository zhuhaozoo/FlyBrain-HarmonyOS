#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MaleCNS v1.0 取数脚本（参考实现）—— 升级迁移文档 §6 阶段 P1
https://male-cns.janelia.org/ · NeuPrint 数据集 male-cns:v1.0（CC BY 4.0）

前置（一次性）：
  1) 到 https://neuprint.janelia.org 注册/登录，Account → New Token 生成 API token；
  2) pip install neuprint pandas

用法：
  NEUPRINT_TOKEN=<你的token> python tools/fetch_malecns.py --out tools/data_malecns
  # 小样试跑（只取前 N 个神经元的连通性）：--limit 2000

导出两份 CSV（build_connectome_malecns.mjs 的输入契约）：
  neurons.csv      bodyId,type,super_class,class,side,x,y,z
  connections.csv  bodyId_pre,bodyId_post,weight[,nt_type]   （按神经元对聚合的邻接表）

说明：
  - 全量邻接表很大（16.6 万神经元，聚合连接千万级），建议内存 ≥16GB、预留 30~60 分钟；
  - 先用 --limit 2000 走通管线再跑全量；
  - 不同 neuprint 版本的返回列名/邻接表结构略有差异：若报 KeyError，请按当时
    neuprint-python 文档微调 normalize_neurons() / write_connections() 两处即可，
    主管线（Node 脚本）对列名是别名宽容的。
"""
import argparse
import os
import re
import sys


def normalize_neurons(df):
    """把 neuprint 的神经元表归一成管线契约的列。"""
    cols = {c.lower(): c for c in df.columns}

    def pick(*names):
        for n in names:
            if n in cols:
                return cols[n]
        return None

    out = []
    idc = pick('bodyid', 'root_id', 'id')
    typec = pick('type', 'cell_type')
    supc = pick('superclass', 'super_class')
    clsc = pick('class', 'cellclass', 'cell_class')
    sidec = pick('side', 'hemi')
    somac = pick('somalocation', 'position', 'soma')
    for _, row in df.iterrows():
        x = y = z = ''
        if somac is not None:
            nums = re.findall(r'[-+0-9.eE]+', str(row[somac] or ''))
            if len(nums) >= 3:
                x, y, z = nums[0], nums[1], nums[2]
        out.append((
            row[idc],
            (row[typec] if typec else '') or '',
            (row[supc] if supc else '') or '',
            (row[clsc] if clsc else '') or '',
            (row[sidec] if sidec else '') or '',
            x, y, z,
        ))
    return out


def write_connections(adj_df, path, limit_ids=None):
    """把邻接表写成 bodyId_pre,bodyId_post,weight[,nt_type]。

    neuprint 的 fetch_adjacency() 可能返回：
      a) 普通/稀疏 DataFrame：index=pre bodyId，columns=post bodyId；或
      b) 带 MultiIndex 列（按 nt 分组）。
    两种都处理；拿不到 nt 时留空（主管线按全正权重处理）。
    """
    nts = None
    cols = adj_df.columns
    if isinstance(cols, __import__('pandas').MultiIndex):
        # 尝试把 nt 放到列的第 0 层
        level0 = [str(x) for x in cols.get_level_values(0)]
        if any(k in ' '.join(level0).lower() for k in ('gaba', 'acetyl', 'glutam', 'unknown')):
            nts = level0
    rows = 0
    with open(path, 'w', encoding='utf-8') as f:
        f.write('bodyId_pre,bodyId_post,weight,nt_type\n')
        for pre in adj_df.index:
            if limit_ids is not None and pre not in limit_ids:
                continue
            row = adj_df.loc[pre]
            if nts is None:
                sub = row[row > 0]
                for post, w in sub.items():
                    if limit_ids is not None and post not in limit_ids:
                        continue
                    f.write(f'{pre},{post},{int(w)},\n')
                    rows += 1
            else:
                for nt_i, nt in enumerate(nts):
                    sub = row[cols[nt_i]][cols[nt_i] > 0]
                    for post, w in sub.items():
                        if limit_ids is not None and post not in limit_ids:
                            continue
                        f.write(f'{pre},{post},{int(w)},{nt}\n')
                        rows += 1
    return rows


def main():
    ap = argparse.ArgumentParser(description='导出 MaleCNS v1.0 神经元表与聚合连接表')
    ap.add_argument('--out', default='tools/data_malecns')
    ap.add_argument('--dataset', default='male-cns:v1.0')
    ap.add_argument('--token', default=os.environ.get('NEUPRINT_TOKEN', ''))
    ap.add_argument('--limit', type=int, default=0, help='小样：只保留前 N 个神经元')
    args = ap.parse_args()
    if not args.token:
        sys.exit('缺少 token：请设置 NEUPRINT_TOKEN 环境变量，或用 --token 传入'
                 '（https://neuprint.janelia.org → Account → New Token）')

    try:
        from neuprint import Client, fetch_neurons, fetch_adjacency, NeuronCriteria
    except ImportError:
        sys.exit('请先安装依赖：pip install neuprint pandas')

    print(f'connecting neuprint dataset={args.dataset} ...')
    Client('https://neuprint.janelia.org', dataset=args.dataset, token=args.token)

    print('fetching neurons ...')
    n_df, _ = fetch_neurons(NeuronCriteria())
    neurons = normalize_neurons(n_df)
    print(f'neurons: {len(neurons)}')

    limit_ids = None
    if args.limit > 0:
        keep = set(n[0] for n in neurons[:args.limit])
        neurons = [n for n in neurons if n[0] in keep]
        limit_ids = keep
        print(f'--limit {args.limit}: 保留 {len(neurons)} 个神经元')

    os.makedirs(args.out, exist_ok=True)
    npath = os.path.join(args.out, 'neurons.csv')
    with open(npath, 'w', encoding='utf-8', newline='') as f:
        f.write('bodyId,type,super_class,class,side,x,y,z\n')
        for (bid, t, sup, cls, side, x, y, z) in neurons:
            f.write(f'{bid},{t},{sup},{cls},{side},{x},{y},{z}\n')
    print(f'wrote {npath}')

    print('fetching adjacency (这一步最大，耐心等) ...')
    adj = fetch_adjacency()
    cpath = os.path.join(args.out, 'connections.csv')
    rows = write_connections(adj, cpath, limit_ids)
    print(f'wrote {cpath} ({rows} 行聚合连接)')

    print('\n完成。下一步：')
    print('  node tools/build_connectome_malecns.mjs --report   # 先看映射覆盖率')
    print('  node tools/build_connectome_malecns.mjs            # 正式生成')


if __name__ == '__main__':
    main()
