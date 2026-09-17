// 场景管理：加载 world.glb、创建相机/平行光、轨道相机控制、
// 查找果蝇节点（M5 多智能体：fly_0..fly_5 各自的子树节点按后缀查找）。
// 依据官方文档《ArkGraphics 3D场景搭建以及管理》：
// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkgraphics3d-scene
import { Camera, Light, LightType, Node, Scene, SceneResourceFactory, Vec3 } from '@kit.ArkGraphics3D';
import { clamp, lookAt, quatMul, quatX, quatY, vec3Cross, vec3Normalize, vec3Sub } from '../common/Math3D';

// 一条腿的四级枢轴关节链（v7.2）。基准站姿已烘进模型网格（枢轴零旋转），
// 渲染层在枢轴上叠加相对旋转：三角步态 / 飞行收腿 / 死亡蜷腿。
// 节点名契约（tools/gen_world_glb.mjs）：leg_{sn}_pivot / _femur_pivot / _tibia_pivot / _tarsus_pivot
export interface LegChain {
  coxa: Node | null;
  femur: Node | null;
  tibia: Node | null;
  tarsus: Node | null;
}

// 一只果蝇的节点集（渲染器 attach 所需的最小集合）
export class FlyNodeSet {
  public fly: Node | null = null;
  public wingL: Node | null = null;
  public wingR: Node | null = null;
  public headPivot: Node | null = null;
  public mouthPivot: Node | null = null;      // 口器枢轴（进食下压，v7 高精度模型）
  public legChains: LegChain[] = [];          // 六条腿的关节链（v7.2 关节链动画）
}

// 场景内烘焙的果蝇数量（与 tools/gen_world_glb.mjs 的烘焙份数一致）
export const BAKED_FLY_COUNT: number = 6;

export class SceneManager {
  public scene: Scene | null = null;
  public camera: Camera | null = null;
  public light: Light | null = null;
  public flySets: FlyNodeSet[] = [];     // 6 份果蝇节点树（M5）
  public skyNodes: Node[] = [];          // 天空穹顶（按时段切换可见）
  public foodNodes: Node[] = [];
  public fruitNodes: Node[] = [];        // 树上果实（M4.2：可落地食用）
  public blockerNodes: Node[] = [];      // 石块碰撞标记（无网格：translation=圆心、scale.x=半径）
  public spotNode: Node | null = null;
  // M4：按名字缓存的场景节点（一次性 DFS 查找，避免每帧查找）
  public extraNodes: Map<string, Node> = new Map<string, Node>();

  // 轨道相机参数（球坐标）
  private yaw: number = Math.PI * 0.85;
  private pitch: number = 0.72;                 // 仰角（弧度），约 41°
  private radius: number = 8.0;
  private readonly minPitch: number = 0.02;
  private readonly maxPitch: number = 1.45;
  private readonly minRadius: number = 1.0;     // 最近可贴近到看清复眼（果蝇体长 0.7，再近会穿模）
  // v6：场地放大到 11.0 后，默认视角 5.6 只能看到场地一半，拉远上限 22 也不够看全景
  private readonly maxRadius: number = 34.0;    // 可拉远看全景（原 22.0 不够）
  private readonly panLimit: number = 13.5;     // 平移范围：注视点可偏离场心的最大水平距离
  private target: Vec3 = { x: 0, y: 0.30, z: 0 }; // 注视点略高于地面
  private lastEye: Vec3 = { x: 0, y: 3, z: 5 };   // applyCamera 后的相机位置
  private userLightFactor: number = 1.0;          // 用户手动光照倍率（明亮 1.0 / 昏暗 0.35 / 黑暗 0.05）
  // 视角追踪：锁定果蝇。person=0 第一人称（贴头部朝前）/ person=1 第三人称（后上方跟随）
  private followMode: boolean = false;
  private followPerson: number = 0;
  private flyX: number = 0;
  private flyZ: number = 0;
  private flyY: number = 0;
  private flyYaw: number = 0;

  // 加载场景并创建相机/光源；返回果蝇节点是否就绪
  async init(): Promise<boolean> {
    try {
      const scene: Scene = await Scene.load($rawfile('gltf/world.glb'));
      this.scene = scene;
      const rf: SceneResourceFactory = scene.getResourceFactory();

      const camera = await rf.createCamera({ name: 'camera' });
      camera.enabled = true;
      camera.nearPlane = 0.05;
      camera.farPlane = 160.0;   // v6：必须 > 天空穹顶半径 56 + 相机最远 34，否则拉到最远时天空被裁
      camera.fov = 55 * Math.PI / 180;
      camera.clearColor = { r: 0.08, g: 0.11, b: 0.15, a: 1.0 }; // 深蓝灰背景
      this.camera = camera;
      this.applyCamera();

      const light = await rf.createLight({ name: 'sun' }, LightType.DIRECTIONAL);
      // 光照方向朝向初始相机一侧（相机初始在 -Z 侧），俯角 45°，避免看到纯黑背面
      light.rotation = quatMul(quatY(Math.PI - 0.5), quatX(-Math.PI / 4));
      light.color = { r: 1.0, g: 0.97, b: 0.90, a: 1.0 };
      light.enabled = true;
      this.light = light;

      // glTF 顶层节点之上存在引擎包裹层，按名字深度搜索而不是猜路径
      const root = scene.root;
      if (!root) {
        console.error('[FlyBrain] scene.root is null');
        return false;
      }
      console.info(`[FlyBrain] root name='${root.name}' path='${root.path}'`);
      // v7.1：一次深度遍历收集全部节点名。此前 130+ 次按名查找各做一遍全树 DFS
      //（每次 900+ 节点的 NAPI 遍历），在真机上会把主线程拖过冻结阈值。
      const all = new Map<string, Node>();
      const scan: Node[] = [root];
      while (scan.length > 0) {
        const cur: Node | undefined = scan.pop();
        if (!cur || !cur.children) {
          continue;
        }
        if (cur.name) {
          all.set(cur.name, cur);
        }
        for (let i = 0; i < cur.children.count(); i++) {
          const ch: Node | null = cur.children.get(i);
          if (ch) {
            scan.push(ch);
          }
        }
      }
      const find = (t: string): Node | null => {
        const n: Node | undefined = all.get(t);
        return n === undefined ? null : n;
      };
      // M5：按后缀查找 6 份果蝇节点树（网格跨果蝇共享，节点名全局唯一）
      this.flySets = [];
      for (let i = 0; i < BAKED_FLY_COUNT; i++) {
      const set = new FlyNodeSet();
      set.fly = find(`fly_${i}`);
      set.wingL = find(`wing_left_${i}`);
      set.wingR = find(`wing_right_${i}`);
      set.headPivot = find(`head_pivot_${i}`);
      set.mouthPivot = find(`mouth_pivot_${i}`);
      const legNames = ['fl', 'fr', 'ml', 'mr', 'hl', 'hr'];
      for (const sn of legNames) {
        const chain: LegChain = {
          coxa: find(`leg_${sn}_pivot_${i}`),
          femur: find(`leg_${sn}_femur_pivot_${i}`),
          tibia: find(`leg_${sn}_tibia_pivot_${i}`),
          tarsus: find(`leg_${sn}_tarsus_pivot_${i}`),
        };
        set.legChains.push(chain);
      }
      this.flySets.push(set);
      }
      this.foodNodes = [];
      for (let i = 0; i < 5; i++) {
        const fn = find(`food_${i}`);
        if (fn) {
          fn.visible = false;
          this.foodNodes.push(fn);
        }
      }
      // 树上果实：9 颗，位置即世界坐标（生成脚本把它们放在树冠处）
      this.fruitNodes = [];
      for (let i = 0; i < 9; i++) {
        const fn = find(`fruit_${i}`);
        if (fn) {
          this.fruitNodes.push(fn);
        }
      }
      this.spotNode = find('lightspot');
      if (this.spotNode) {
        (this.spotNode as Node).visible = false;
      }
      // 场内静态阻挡标记节点（blocker_0..N-1：石块/河岸卵石/树干，无网格）。
      // 数量由生成脚本决定（当前 33），这里按序号顺序收集直到找不到为止（不硬编码个数）
      this.blockerNodes = [];
      for (let i = 0; i < 64; i++) {
        const bn = find(`blocker_${i}`);
        if (bn === null) {
          break;
        }
        this.blockerNodes.push(bn);
      }
      this.registerExtra(find);
      if (this.flySets.length === 0 || this.flySets[0].fly === null) {
        this.dumpTree(root, 40);
      }
      const leadOk = this.flySets.length > 0 && this.flySets[0].fly !== null &&
        this.flySets[0].fly !== undefined;
      // 关节链必须点名计数：模型缺枢轴时动画会静默退化（易错总结第 35 条同类）
      let leadLegs = 0;
      if (this.flySets.length > 0) {
        for (const lc of this.flySets[0].legChains) {
          if (lc.coxa !== null && lc.femur !== null && lc.tibia !== null && lc.tarsus !== null) {
            leadLegs++;
          }
        }
      }
      console.info(`[FlyBrain] nodes found: flySets=${this.flySets.length}, ` +
        `leadFly=${leadOk}, legChains=${leadLegs}/6, food=${this.foodNodes.length}, ` +
        `spot=${this.spotNode !== null}, blockers=${this.blockerNodes.length}, ` +
        `extra=${this.extraNodes.size}`);
      return leadOk;
    } catch (err) {
      console.error(`[FlyBrain] Scene init failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  // M4：一次性注册需要按名字访问的节点，并隐藏所有特效节点（事件期间才显示）
  private registerExtra(find: (t: string) => Node | null): void {
    const names: string[] = [
      // 环境（注意是 sun_disc / moon_disc：'sun' 这个名字被平行光占用了）
      'sun_pivot', 'sun_disc', 'moon_pivot', 'moon_disc', 'stars', 'river',
      // 树木（一级/二级摇摆驱动点）
      'trunk_0', 'trunk_1', 'trunk_2', 'crown_0', 'crown_1', 'crown_2',
      // 青蛙
      'frog', 'frog_body', 'frog_tongue', 'frog_eye_l', 'frog_eye_r',
      'frog_pupil_l', 'frog_pupil_r',
    ];
    for (const n of names) {
      const node = find(n);
      if (node) {
        this.extraNodes.set(n, node);
      }
    }
    // 特效节点：plus_fx / wind_line / ripple / path_dot
    const fxGroups: string[] = ['plus_fx', 'wind_line', 'ripple', 'path_dot'];
    const fxCounts: number[] = [3, 6, 3, 6];
    for (let g = 0; g < fxGroups.length; g++) {
      for (let i = 0; i < fxCounts[g]; i++) {
        const key = `${fxGroups[g]}_${i}`;
        const node = find(key);
        if (node) {
          node.visible = false; // 常态隐藏，事件期间由控制器打开
          this.extraNodes.set(key, node);
        }
      }
    }
    // 天空穹顶：glTF 没有节点级 visible，加载后先全部隐藏，
    // 再由 EnvironmentController 每帧只打开当前时段对应的那一个
    this.skyNodes = [];
    for (let i = 0; i < this.cfgSkyDomeCount(); i++) {
      const key = `sky_${i}`;
      const node = find(key);
      if (node) {
        node.visible = false;
        this.skyNodes.push(node);
        this.extraNodes.set(key, node);
      }
    }
    console.info(`[FlyBrain] sky domes registered: ${this.skyNodes.length}/${this.cfgSkyDomeCount()}`);
  }

  // 天空穹顶数量（与生成脚本 SKY_HEX 长度一致，这里避免引用 FlyConfig 造成耦合）
  private cfgSkyDomeCount(): number {
    return 9;
  }

  // 取 M4 节点（未注册/不存在返回 null）
  getNode(name: string): Node | null {
    const n = this.extraNodes.get(name);
    return n === undefined ? null : n;
  }

  // 单指拖拽 → 环绕视角（dx/dy 为像素增量）
  orbitByPixels(dx: number, dy: number): void {
    this.yaw -= dx * 0.0075;
    this.pitch = clamp(this.pitch + dy * 0.005, this.minPitch, this.maxPitch);
    this.applyCamera();
  }

  // 双指拖拽 → 平移视角：把注视点在水平面上移动（"抓住地面拖动"的手感）。
  // 追踪模式下相机锁在果蝇身上，平移无意义，直接忽略。
  // viewportH 是 3D 组件的高度（vp），用来把像素增量换算成世界单位：
  // 注视点处一屏高度对应的世界高度 = 2 × radius × tan(fov/2)。
  panByPixels(dx: number, dy: number, viewportH: number): void {
    if (!this.camera || this.followMode) {
      return;
    }
    const h = viewportH > 1 ? viewportH : 1;
    const s = 2 * this.radius * Math.tan(this.camera.fov / 2) / h;
    const f = vec3Normalize(vec3Sub(this.target, this.lastEye));
    const right = vec3Normalize(vec3Cross(f, { x: 0, y: 1, z: 0 }));
    // 屏幕"上方"在世界里的水平方向：前向在地面的投影（正俯视时退化为 0，此时只按左右平移）
    let gx = f.x;
    let gz = f.z;
    const gl = Math.hypot(gx, gz);
    if (gl > 1e-4) {
      gx = gx / gl;
      gz = gz / gl;
    } else {
      gx = 0;
      gz = 0;
    }
    // 手指右移 → 注视点左移；手指下移 → 注视点向远处移（地面跟着手指走）
    const nx = this.target.x - right.x * dx * s + gx * dy * s;
    const nz = this.target.z - right.z * dx * s + gz * dy * s;
    // 钳制：注视点只在地盘附近移动，避免用户一键"迷路"到空场外
    const r = Math.hypot(nx, nz);
    const k = r > this.panLimit ? this.panLimit / r : 1;
    this.target.x = nx * k;
    this.target.z = nz * k;
    this.applyCamera();
  }

  // 重置注视点（「重置视角」按钮）：回到场心
  resetTarget(): void {
    this.target.x = 0;
    this.target.z = 0;
    this.applyCamera();
  }

  getRadius(): number {
    return this.radius;
  }

  getRadiusRange(): number[] {
    return [this.minRadius, this.maxRadius];
  }

  // 视角追踪开关：开启后相机锁定果蝇
  setFollowMode(on: boolean): void {
    this.followMode = on;
    this.applyCamera();
  }

  isFollowMode(): boolean {
    return this.followMode;
  }

  // 跟随视角类型：0 第一人称 / 1 第三人称
  setFollowPerson(p: number): void {
    this.followPerson = p;
    this.applyCamera();
  }

  getFollowPerson(): number {
    return this.followPerson;
  }

  // 记录果蝇当前位置（追踪模式与交互定位使用）。
  // 注意：这里**不再**把相机注视点逐帧拉向果蝇 —— 那样会让用户在拖拽转视角后
  // 视角被自动"吸"回果蝇身上，无法自由观察场景。注视点只由用户操作（拖拽/缩放/追踪开关）改变。
  followFly(x: number, z: number): void {
    this.flyX = x;
    this.flyZ = z;
  }

  // 追踪模式下每帧写入果蝇完整位姿（位置 + 高度 + 朝向）
  setFlyPose(x: number, y: number, z: number, yaw: number): void {
    this.flyX = x;
    this.flyY = y;
    this.flyZ = z;
    this.flyYaw = yaw;
    if (this.followMode) {
      this.applyCamera();
    }
  }

  // 用户手动光照档位（0 黑暗 / 0.5 昏暗 / 1 明亮）→ 倍率。
  // 注意：平行光的 intensity 自 M4 起由 EnvironmentController 统一写入（它要叠加昼夜曲线），
  // 这里只换算倍率，不再直接改 intensity —— 避免出现两个写入者互相覆盖。
  setLightLevel(level: number): void {
    this.userLightFactor = level === 0 ? 0.05 : (level === 0.5 ? 0.35 : 1.0);
  }

  getUserLightFactor(): number {
    return this.userLightFactor;
  }

  // 屏幕归一化坐标 (u,v)（组件内左上角为原点）反投影到地面 y≈0 平面
  groundPoint(u: number, v: number, aspect: number): Vec3 | null {
    if (!this.camera) {
      return null;
    }
    const f = vec3Normalize(vec3Sub(this.target, this.lastEye));
    const right = vec3Normalize(vec3Cross(f, { x: 0, y: 1, z: 0 }));
    const camUp = vec3Cross(right, f);
    const tanF = Math.tan((this.camera.fov) / 2);
    const ndcX = u * 2 - 1;
    const ndcY = 1 - v * 2;
    const dir = vec3Normalize({
      x: f.x + right.x * ndcX * aspect * tanF + camUp.x * ndcY * tanF,
      y: f.y + right.y * ndcX * aspect * tanF + camUp.y * ndcY * tanF,
      z: f.z + right.z * ndcX * aspect * tanF + camUp.z * ndcY * tanF,
    });
    if (dir.y >= -1e-4) {
      return null; // 视线朝天，打不到地面
    }
    const t = (0.02 - this.lastEye.y) / dir.y;
    return { x: this.lastEye.x + dir.x * t, y: 0.02, z: this.lastEye.z + dir.z * t };
  }

  setRadius(r: number): void {
    this.radius = clamp(r, this.minRadius, this.maxRadius);
    this.applyCamera();
  }

  // 球坐标 → 相机位置，并 lookAt 注视点
  private applyCamera(): void {
    if (!this.camera) {
      return;
    }
    // 追踪模式：锁定果蝇（第一人称 / 第三人称）
    if (this.followMode) {
      const fx = Math.sin(this.flyYaw);
      const fz = Math.cos(this.flyYaw);
      let eye: Vec3;
      let center: Vec3;
      if (this.followPerson === 0) {
        // 第一人称：相机置于果蝇头部（前方 0.18、高 0.22 —— 随 v5.1 体型 0.6 等比缩小），
        // 朝前进方向看。注意不能"从身体后方看"——后拉距离太小时画面会被自己躯干填满
        const headFwd = 0.18;
        eye = {
          x: this.flyX + fx * headFwd,
          y: this.flyY + 0.22,
          z: this.flyZ + fz * headFwd,
        };
        center = {
          x: this.flyX + fx * 9.0,
          y: this.flyY + 0.17,
          z: this.flyZ + fz * 9.0,
        };
      } else {
        // 第三人称：相机在果蝇后上方，注视果蝇本体（距离随缩放滑杆变化）。
        // v6：拉远上限提到 34 后距离会到 10 —— 果蝇会缩成一个点。这里对"后撤距离 + 抬高"
        // 同比限幅（而不是硬砍距离），保证拉到最远时构图与原来一致，只是不再继续远离。
        const raw = 0.55 + this.radius * 0.28;
        const k = Math.min(1, 6.0 / raw);
        const dist = raw * k;
        const height = (0.30 + this.radius * 0.10) * k;
        eye = {
          x: this.flyX - fx * dist,
          y: this.flyY + height,
          z: this.flyZ - fz * dist,
        };
        center = {
          x: this.flyX,
          y: this.flyY + 0.15,
          z: this.flyZ,
        };
      }
      this.lastEye = eye;
      lookAt(this.camera, eye, center, { x: 0, y: 1, z: 0 });
      return;
    }
    const cp = Math.cos(this.pitch);
    const eye: Vec3 = {
      x: this.target.x + this.radius * cp * Math.sin(this.yaw),
      y: this.target.y + this.radius * Math.sin(this.pitch),
      z: this.target.z + this.radius * cp * Math.cos(this.yaw),
    };
    this.lastEye = eye;
    lookAt(this.camera, eye, this.target, { x: 0, y: 1, z: 0 });
  }

  // 按名字深度优先搜索节点（glTF 顶层节点之上可能有引擎包裹层，路径不可预知）
  private findByName(root: Node, target: string): Node | null {
    if (root.name === target) {
      return root;
    }
    const stack: Node[] = [root];
    while (stack.length > 0) {
      const cur: Node | undefined = stack.pop();
      if (!cur || !cur.children) {
        continue;
      }
      const kids = cur.children;
      for (let i = 0; i < kids.count(); i++) {
        const ch: Node | null = kids.get(i);
        if (!ch) {
          continue;
        }
        if (ch.name === target) {
          return ch;
        }
        stack.push(ch);
      }
    }
    return null;
  }

  // 打印节点树（查找失败时的诊断输出）
  private dumpTree(root: Node, maxNodes: number): void {
    let printed = 0;
    const stack: Node[] = [root];
    while (stack.length > 0 && printed < maxNodes) {
      const cur: Node | undefined = stack.pop();
      if (!cur) {
        continue;
      }
      console.info(`[FlyBrain] tree: name='${cur.name}' path='${cur.path}'`);
      printed++;
      if (!cur.children) {
        continue;
      }
      for (let i = 0; i < cur.children.count(); i++) {
        const ch: Node | null = cur.children.get(i);
        if (ch) {
          stack.push(ch);
        }
      }
    }
  }
}
