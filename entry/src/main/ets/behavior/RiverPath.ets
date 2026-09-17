// 蜿蜒河道（纯逻辑，M5 v7 场景升级配套）：中心折线 + 半宽的水带几何。
// 中心线采样点来自生成脚本 RIVER_SAMPLES（FlyConfig.riverPts 逐点一致，尺度成对常量）。
// 使用方：FlyBrain（水检测/推岸）、FoodWorld（食物落点避河）。
export class RiverNearest {
  public d: number = 0;    // 到中心线最近距离
  public cx: number = 0;   // 最近点
  public cz: number = 0;
  public nx: number = 0;   // 法向（从最近点指向查询点一侧）
  public nz: number = 0;
}

export class RiverPath {
  private xs: number[] = [];
  private zs: number[] = [];
  private half: number = 0.7;

  constructor(pts: number[], half: number) {
    for (let i = 0; i + 1 < pts.length; i += 2) {
      this.xs.push(pts[i]);
      this.zs.push(pts[i + 1]);
    }
    this.half = half;
  }

  nearest(x: number, z: number): RiverNearest {
    const r = new RiverNearest();
    r.d = Infinity;
    const n = this.xs.length;
    for (let i = 0; i < n - 1; i++) {
      const ax = this.xs[i], az = this.zs[i];
      const bx = this.xs[i + 1], bz = this.zs[i + 1];
      const dx = bx - ax, dz = bz - az;
      const l2 = dx * dx + dz * dz;
      let t = l2 > 1e-9 ? ((x - ax) * dx + (z - az) * dz) / l2 : 0;
      t = Math.max(0, Math.min(1, t));
      const cx = ax + dx * t, cz = az + dz * t;
      const d = Math.hypot(x - cx, z - cz);
      if (d < r.d) {
        r.d = d; r.cx = cx; r.cz = cz;
        const l = Math.sqrt(l2) || 1;
        r.nx = -dz / l; r.nz = dx / l;
        if ((x - cx) * r.nx + (z - cz) * r.nz < 0) { r.nx = -r.nx; r.nz = -r.nz; }
      }
    }
    return r;
  }

  isWater(x: number, z: number): boolean {
    return this.nearest(x, z).d < this.half;
  }

  // 距水 ≤ band（岸边缓冲带，饮水判定用）
  isNearWater(x: number, z: number, band: number): boolean {
    return this.nearest(x, z).d < this.half + band;
  }

  // 若点在水带内：沿法向推到 half+margin 的近岸，返回 true 并把推出后坐标写进 r
  //（r.cx/r.cz = 推出后的位置；r.nx/r.nz = 指向该侧的法向，供沿岸滑动定向）
  pushOut(x: number, z: number, margin: number, r: RiverNearest): boolean {
    const n = this.nearest(x, z);
    r.d = n.d; r.cx = n.cx; r.cz = n.cz; r.nx = n.nx; r.nz = n.nz;
    if (n.d >= this.half) {
      return false;
    }
    const bank = this.half + margin;
    r.cx = n.cx + n.nx * bank;
    r.cz = n.cz + n.nz * bank;
    return true;
  }
}
