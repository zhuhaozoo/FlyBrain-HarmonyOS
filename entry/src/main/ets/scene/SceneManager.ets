// 场景管理：加载 world.glb、创建相机/平行光、轨道相机控制、
// 查找果蝇节点（fly / fly/wing_left / fly/wing_right）。
// 依据官方文档《ArkGraphics 3D场景搭建以及管理》：
// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkgraphics3d-scene
import { Camera, Light, LightType, Node, Scene, SceneResourceFactory, Vec3 } from '@kit.ArkGraphics3D';
import { clamp, lookAt, quatMul, quatX, quatY, vec3Cross, vec3Normalize, vec3Sub } from '../common/Math3D';

export class SceneManager {
  public scene: Scene | null = null;
  public camera: Camera | null = null;
  public light: Light | null = null;
  public flyNode: Node | null = null;
  public wingLeft: Node | null = null;
  public wingRight: Node | null = null;
  public foodNodes: Node[] = [];
  public spotNode: Node | null = null;

  // 轨道相机参数（球坐标）
  private yaw: number = Math.PI * 0.85;
  private pitch: number = 0.72;                 // 仰角（弧度），约 41°
  private radius: number = 5.6;
  private readonly minPitch: number = 0.02;
  private readonly maxPitch: number = 1.45;
  private readonly minRadius: number = 1.0;     // 最近可贴近到看清复眼（果蝇体长 0.7，再近会穿模）
  private readonly maxRadius: number = 22.0;    // 可拉远看全景（原 11.0 不够）
  private target: Vec3 = { x: 0, y: 0.30, z: 0 }; // 注视点略高于地面
  private lastEye: Vec3 = { x: 0, y: 3, z: 5 };   // applyCamera 后的相机位置
  private baseIntensity: number = -1;             // 平行光默认强度（首次读取）
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
      camera.farPlane = 80.0;
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
      this.flyNode = this.findByName(root, 'fly');
      this.wingLeft = this.findByName(root, 'wing_left');
      this.wingRight = this.findByName(root, 'wing_right');
      this.foodNodes = [];
      for (let i = 0; i < 5; i++) {
        const fn = this.findByName(root, `food_${i}`);
        if (fn) {
          fn.visible = false;
          this.foodNodes.push(fn);
        }
      }
      this.spotNode = this.findByName(root, 'lightspot');
      if (this.spotNode) {
        (this.spotNode as Node).visible = false;
      }
      if (!this.flyNode) {
        this.dumpTree(root, 40);
      }
      console.info(`[FlyBrain] nodes found: fly=${this.flyNode !== null}, ` +
        `wingL=${this.wingLeft !== null}, wingR=${this.wingRight !== null}, ` +
        `food=${this.foodNodes.length}, spot=${this.spotNode !== null}`);
      return this.flyNode !== null && this.flyNode !== undefined;
    } catch (err) {
      console.error(`[FlyBrain] Scene init failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  // 单指拖拽 → 环绕视角（dx/dy 为像素增量）
  orbitByPixels(dx: number, dy: number): void {
    this.yaw -= dx * 0.0075;
    this.pitch = clamp(this.pitch + dy * 0.005, this.minPitch, this.maxPitch);
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

  // 注视点平滑跟随果蝇（钳制在场地内，避免相机跑到场景外）
  followFly(x: number, z: number): void {
    this.flyX = x;
    this.flyZ = z;
    if (this.followMode) {
      return; // 追踪模式由 setFlyPose 每帧直接驱动
    }
    const k = 0.12;
    // 钳制到场地半径内：近景时果蝇必须始终在画面中，远景时可略有滞后
    const lim = this.cfgArenaRadius();
    const tx = clamp(x, -lim, lim);
    const tz = clamp(z, -lim, lim);
    this.target.x += (tx - this.target.x) * k;
    this.target.z += (tz - this.target.z) * k;
  }

  private cfgArenaRadius(): number {
    return 4.0; // 与 FlyConfig.arenaRadius(4.6) 同量级，保证果蝇始终在视野内
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

  // 光照档位（0 黑暗 / 0.5 昏暗 / 1 明亮）：按首帧读取的默认强度等比缩放
  setLightLevel(level: number): void {
    if (!this.light) {
      return;
    }
    if (this.baseIntensity < 0) {
      this.baseIntensity = this.light.intensity;
      console.info(`[FlyBrain] light base intensity=${this.baseIntensity}`);
    }
    const factor = level === 0 ? 0.05 : (level === 0.5 ? 0.35 : 1.0);
    this.light.intensity = this.baseIntensity * factor;
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
        // 第一人称：相机置于果蝇头部（前方 0.3、高 0.36），朝前进方向看
        // 注意不能"从身体后方看"——果蝇体长 0.7，后拉距离太小时画面会被自己躯干填满
        const headFwd = 0.30;
        eye = {
          x: this.flyX + fx * headFwd,
          y: this.flyY + 0.36,
          z: this.flyZ + fz * headFwd,
        };
        center = {
          x: this.flyX + fx * 6.0,
          y: this.flyY + 0.28,
          z: this.flyZ + fz * 6.0,
        };
      } else {
        // 第三人称：相机在果蝇后上方，注视果蝇本体（距离随缩放滑杆变化）
        const dist = 0.85 + this.radius * 0.28;
        const height = 0.42 + this.radius * 0.10;
        eye = {
          x: this.flyX - fx * dist,
          y: this.flyY + height,
          z: this.flyZ - fz * dist,
        };
        center = {
          x: this.flyX,
          y: this.flyY + 0.24,
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
