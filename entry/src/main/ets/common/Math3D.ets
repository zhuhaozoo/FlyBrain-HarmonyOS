// 3D 数学工具：向量/四元数 + 相机 lookAt。
// lookAt 的矩阵→四元数推导方式参考华为官方 Graphics3D 示例工程的 CalcUtils.ets
// （https://gitcode.com/HarmonyOS_Samples/Graphics3D，Apache License 2.0），
// 本实现为独立编写版本，保留原许可声明。
import { Camera, Quaternion, Vec3 } from '@kit.ArkGraphics3D';

export function vec3Sub(l: Vec3, r: Vec3): Vec3 {
  return { x: l.x - r.x, y: l.y - r.y, z: l.z - r.z };
}

export function vec3Dot(l: Vec3, r: Vec3): number {
  return l.x * r.x + l.y * r.y + l.z * r.z;
}

export function vec3Cross(l: Vec3, r: Vec3): Vec3 {
  return {
    x: l.y * r.z - l.z * r.y,
    y: l.z * r.x - l.x * r.z,
    z: l.x * r.y - l.y * r.x,
  };
}

export function vec3Normalize(l: Vec3): Vec3 {
  const d = Math.sqrt(vec3Dot(l, l));
  if (d <= 1e-8) {
    return { x: 0, y: 0, z: 0 };
  }
  return { x: l.x / d, y: l.y / d, z: l.z / d };
}

// 把相机放到 eye 处并使其朝向 center（up 为世界上方向）
export function lookAt(cam: Camera, eye: Vec3, center: Vec3, up: Vec3): void {
  const f = vec3Normalize(vec3Sub(center, eye)); // 前 = -Z
  const right = vec3Normalize(vec3Cross(f, up)); // 右 = +X
  const camUp = vec3Cross(right, f);             // 上 = +Y
  const back: Vec3 = { x: -f.x, y: -f.y, z: -f.z }; // +Z（相机看向 -Z）

  // 旋转矩阵（列 = right / camUp / back）转四元数
  const m00 = right.x, m10 = right.y, m20 = right.z;
  const m01 = camUp.x, m11 = camUp.y, m21 = camUp.z;
  const m02 = back.x, m12 = back.y, m22 = back.z;

  const trace = m00 + m11 + m22;
  let q: Quaternion = { x: 0, y: 0, z: 0, w: 1 };
  if (trace > 0) {
    const s = Math.sqrt(trace + 1.0) * 2;
    q = { x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: 0.25 * s };
  } else if (m00 > m11 && m00 > m22) {
    const s = Math.sqrt(1.0 + m00 - m11 - m22) * 2;
    q = { x: 0.25 * s, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s };
  } else if (m11 > m22) {
    const s = Math.sqrt(1.0 + m11 - m00 - m22) * 2;
    q = { x: (m01 + m10) / s, y: 0.25 * s, z: (m12 + m21) / s, w: (m02 - m20) / s };
  } else {
    const s = Math.sqrt(1.0 + m22 - m00 - m11) * 2;
    q = { x: (m02 + m20) / s, y: (m12 + m21) / s, z: 0.25 * s, w: (m10 - m01) / s };
  }

  cam.position = eye;
  cam.rotation = q;
}

// 四元数相乘（先应用 b，再应用 a）
export function quatMul(a: Quaternion, b: Quaternion): Quaternion {
  return {
    x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
  };
}

// 绕 Y 轴的四元数（果蝇朝向，0 弧度时朝 +Z）
export function quatY(angle: number): Quaternion {
  return { x: 0, y: Math.sin(angle / 2), z: 0, w: Math.cos(angle / 2) };
}

// 绕 Z 轴的四元数（翅膀上下摆动）
export function quatZ(angle: number): Quaternion {
  return { x: 0, y: 0, z: Math.sin(angle / 2), w: Math.cos(angle / 2) };
}

// 绕 X 轴的四元数（平行光俯角）
export function quatX(angle: number): Quaternion {
  return { x: Math.sin(angle / 2), y: 0, z: 0, w: Math.cos(angle / 2) };
}

// 角度归一化到 [-PI, PI]
export function normalizeAngle(a: number): number {
  let r = a % (2 * Math.PI);
  if (r > Math.PI) {
    r -= 2 * Math.PI;
  }
  if (r < -Math.PI) {
    r += 2 * Math.PI;
  }
  return r;
}

export function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}
