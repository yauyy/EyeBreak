'use strict';

(() => {
  // 沿用 TomatoCharacter.swift 的 100×100 坐标与配色；新动作的纯时间公式供后续逐行移植。
  const INK = '#4A3428';
  const TAU = Math.PI * 2;
  const handOutline = { rx: 8.05, ry: 7, strokeWidth: 2.2 };
  const footOutline = { rx: 7.5, ry: 4.1, strokeWidth: 2.2 };
  // 第 5 轮：基准不动，优先保住眼睛/嘴和手脚的连续间距；按 0.001 精度向下取安全摆幅。
  const walkHandMotion = { forwardLift: 3.687, forwardInset: 2.4, backwardDrop: 1.161 };
  const faceOutline = {
    eyes: [37, 63].map(x => ({ x, y: 60, rx: 5.6, ry: 6.9 })),
    blush: [28, 72].map(x => ({ x, y: 69.7, rx: 5.8, ry: 3.2 })),
    mouth: { curves: [[46.6, 67.5, 48.3, 71, 50, 67.5], [50, 67.5, 51.7, 71, 53.4, 67.5]], strokeWidth: 1.8 }
  };
  const representativeTime = { still: 0, lookFar: 1.8, blink: 0.78, closeEyes: 0, rollEyes: 1.5, drinkWater: 1.4, walk: 0.45 };
  const phase = (t, duration) => ((t % duration) + duration) % duration;
  const ease = value => (1 - Math.cos(Math.PI * Math.max(0, Math.min(1, value)))) / 2;
  const circleAngle = t => -Math.PI / 2 + TAU * ease(phase(t, 3) / 3);

  function frame(motion, t) {
    const state = { lookX: 0, lookY: 0, closure: 0, gaze: 0, breath: 0, angle: 0, lift: 0, sip: 0, cupX: 0, cupY: 0, cupRotation: 0, handX: 0, handY: 0, walkSwing: 0, leftStep: 0, rightStep: 0, walkBob: 0, walkShift: 0, walkSway: 0, walkSquash: 0 };
    if (motion === 'lookFar') {
      const p = phase(t, 4);
      state.gaze = p < 1.2 ? ease(p / 1.2) : p < 2.3 ? 1 : p < 3.5 ? 1 - ease((p - 2.3) / 1.2) : 0;
      state.lookX = 3 * state.gaze;
      state.lookY = -3 * state.gaze;
    } else if (motion === 'blink') {
      // 6.4 秒里有三次常规眨眼，最后一次紧接着补眨一下。
      const p = phase(t, 6.4);
      for (const start of [0.65, 2.65, 4.65, 5.03]) {
        const d = p - start;
        const closure = d < 0 || d >= 0.28 ? 0 : d < 0.13 ? ease(d / 0.13) : 1 - ease((d - 0.13) / 0.15);
        state.closure = Math.max(state.closure, closure);
      }
    } else if (motion === 'closeEyes') {
      state.breath = (1 - Math.cos(TAU * phase(t, 4) / 4)) / 2;
    } else if (motion === 'rollEyes') {
      state.angle = circleAngle(t);
      state.lookX = 3 * Math.cos(state.angle);
      state.lookY = 3 * Math.sin(state.angle);
    } else if (motion === 'drinkWater') {
      // 四秒一轮：抬杯、两次轻啜、放下、停顿；各段接点的位置和速度连续。
      const p = phase(t, 4);
      state.lift = p < 1 ? ease(p) : p < 2.6 ? 1 : p < 3.6 ? 1 - ease(p - 2.6) : 0;
      state.sip = p >= 1 && p < 2.6 ? Math.sin(TAU * (p - 1) / 1.6) ** 2 : 0;
      state.closure = ease((state.lift - 0.55) / 0.45);
      // 以杯身中心定位；杯口向左上靠嘴，圆手贴住杯身右侧中下部。
      state.cupX = 68.5 - 13.7 * state.lift;
      state.cupY = 80 - 2.3 * state.lift - 0.35 * state.sip;
      state.cupRotation = -22 * state.lift - 4 * state.sip;
      const angle = state.cupRotation * Math.PI / 180;
      state.handX = state.cupX + 9.7 * Math.cos(angle) - 2 * Math.sin(angle);
      state.handY = state.cupY + 9.7 * Math.sin(angle) + 2 * Math.cos(angle);
    } else if (motion === 'walk') {
      // 3.6 秒四步，左右各两步；起止各 0.225 秒缓入缓出，站姿接点的速度也归零。
      const p = phase(t, 3.6);
      const stride = Math.sin(TAU * p / 1.8);
      const settle = ease(Math.min(p, 3.6 - p) / 0.225);
      state.walkSwing = stride * settle;
      // 半波平方让脚落地时速度为零；正半波抬左脚，负半波抬右脚。
      state.leftStep = Math.max(0, stride) ** 2 * settle;
      state.rightStep = Math.max(0, -stride) ** 2 * settle;
      state.walkBob = 2 * (state.leftStep + state.rightStep);
      state.walkShift = 1.5 * state.walkSwing;
      state.walkSway = 4.5 * state.walkSwing;
      // 站姿基准不变；仅收小前摆抬高、微调内收和后摆下沉，手掌允许压到腮红。
      const { forwardLift, forwardInset, backwardDrop } = walkHandMotion;
      state.walkHands = [
        { x: 22.5 + forwardInset * state.rightStep - 0.5 * state.leftStep, y: 75.8 + backwardDrop * state.leftStep - forwardLift * state.rightStep },
        { x: 77.5 - forwardInset * state.leftStep + 0.5 * state.rightStep, y: 75.8 + backwardDrop * state.rightStep - forwardLift * state.leftStep }
      ];
      // 仅中途换步时短促压扁 2%；接触前后各 0.16 秒余弦缓动，首尾保持原站姿。
      const landing = Math.round(p / 0.9) * 0.9;
      const impact = landing > 0 && landing < 3.6 ? 1 - ease(Math.abs(p - landing) / 0.16) : 0;
      state.walkSquash = 0.02 * impact;
    }
    return state;
  }

  function ellipse(ctx, x, y, rx, ry, color, rotation = 0) {
    ctx.beginPath();
    ctx.ellipse(x, y, rx, ry, rotation, 0, TAU);
    ctx.fillStyle = color;
    ctx.fill();
  }

  function stroke(ctx, build, width, color = INK) {
    ctx.beginPath();
    build(ctx);
    ctx.lineWidth = width;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = color;
    ctx.stroke();
  }

  function tomatoGradient(ctx) {
    const gradient = ctx.createRadialGradient(40, 46, 2, 40, 46, 46);
    gradient.addColorStop(0, '#FF9A82');
    gradient.addColorStop(1, '#F0453A');
    return gradient;
  }

  function drawBody(ctx) {
    ctx.beginPath();
    ctx.ellipse(50, 60, 38, 33, 0, 0, TAU);
    ctx.strokeStyle = INK; ctx.lineWidth = 4.8; ctx.stroke();
    ctx.fillStyle = tomatoGradient(ctx); ctx.fill();
    ellipse(ctx, 37, 45, 6.5, 3.2, 'rgba(255,255,255,.55)', -32 * Math.PI / 180);
    ellipse(ctx, 43.3, 40.3, 1.3, 1.3, 'rgba(255,255,255,.7)');
  }

  function drawLeaves(ctx) {
    ctx.beginPath();
    for (const k of [-144, -72, 0, 72, 144]) {
      const a = (k - 90) * Math.PI / 180;
      const x = 50 + Math.cos(a) * 8.4;
      const y = 31 + Math.sin(a) * 8.4;
      ctx.moveTo(x + 9.6 * Math.cos(a), y + 9.6 * Math.sin(a));
      ctx.ellipse(x, y, 9.6, 3.9, a, 0, TAU);
      ctx.closePath();
    }
    ctx.lineWidth = 4.4; ctx.strokeStyle = INK; ctx.lineJoin = 'round'; ctx.stroke();
    ctx.fillStyle = '#5BCB6E'; ctx.fill();
    const stem = c => { c.moveTo(50, 30); c.quadraticCurveTo(49.2, 21, 54, 15.5); };
    stroke(ctx, stem, 6.4);
    stroke(ctx, stem, 2.2, '#3E9E52');
  }

  function closedEye(ctx, x, y) {
    stroke(ctx, c => { c.moveTo(x - 5.4, y); c.quadraticCurveTo(x, y + 5.6, x + 5.4, y); }, 2.2);
  }

  function openEye(ctx, x, y, closure, closedDepth = 3) {
    ctx.save();
    // 眼珠保持原尺寸，用上下眼皮围成的开口裁切，上眼皮真实落下。
    const top = y - 6.9 * (1 - closure);
    const bottom = y + 6.9 * (1 - closure);
    ctx.beginPath();
    ctx.moveTo(x - 5.9, top);
    ctx.quadraticCurveTo(x, top + closedDepth * closure, x + 5.9, top);
    ctx.lineTo(x + 5.9, bottom);
    ctx.quadraticCurveTo(x, bottom + closedDepth * closure, x - 5.9, bottom);
    ctx.closePath(); ctx.clip();
    ellipse(ctx, x, y, 5.6, 6.9, '#3B2A22');
    ctx.save();
    ctx.beginPath(); ctx.ellipse(x, y, 5.6, 6.9, 0, 0, TAU); ctx.clip();
    ellipse(ctx, x, y + 5.865, 5.32, 3.45, 'rgba(255,255,255,.2)');
    ctx.restore();
    ellipse(ctx, x - 1.568, y - 2.484, 2.24, 2.208, '#FFFFFF');
    ellipse(ctx, x + 2.016, y + 2.208, 0.952, 0.952, '#FFFFFF');
    ctx.restore();
    if (closure > 0) {
      stroke(ctx, c => { c.moveTo(x - 5.4, top); c.quadraticCurveTo(x, top + closedDepth * closure, x + 5.4, top); }, 2.2, `rgba(74,52,40,${closure})`);
    }
  }

  function drawFace(ctx, motion, state) {
    for (const { x } of faceOutline.eyes) {
      if (motion === 'closeEyes') closedEye(ctx, x, 60);
      // 喝水时连续落下眼皮，最终与 closedEye 的 5.6 深度弧线完全一致。
      else openEye(ctx, x + state.lookX, 60 + state.lookY, state.closure, motion === 'drinkWater' ? 5.6 : 3);
    }
    for (const { x, y, rx, ry } of faceOutline.blush) ellipse(ctx, x, y, rx, ry, 'rgba(255,110,140,.42)');
    stroke(ctx, c => {
      const [first] = faceOutline.mouth.curves;
      c.moveTo(first[0], first[1]);
      for (const curve of faceOutline.mouth.curves) c.quadraticCurveTo(...curve.slice(2));
    }, faceOutline.mouth.strokeWidth);
  }

  function drawArm(ctx, rootX, rootY, bendX, bendY, x, y) {
    const arm = c => { c.moveTo(rootX, rootY); c.quadraticCurveTo(bendX, bendY, x, y); };
    // 同一条二次曲线叠画成实心圆头管子；根部圆端与身体重叠。
    stroke(ctx, arm, 11);
    stroke(ctx, arm, 7, '#F0453A');
  }

  function drawHand(ctx, x, y, rotation, scale = 1) {
    // 手掌宽高比 1.15，高光和底部暖色随手掌旋转。
    ctx.save();
    ctx.translate(x, y); ctx.rotate(rotation * Math.PI / 180); ctx.scale(scale, scale);
    ellipse(ctx, 0, 0, handOutline.rx, handOutline.ry, '#FFFDF8');
    ctx.save();
    ctx.beginPath(); ctx.ellipse(0, 0, handOutline.rx, handOutline.ry, 0, 0, TAU); ctx.clip();
    ellipse(ctx, 0, 4.1, 7, 2.6, '#F4EBDD');
    ellipse(ctx, -2.6, -3, 2.8, 1.6, '#FFFFFF', -32 * Math.PI / 180);
    ctx.restore();
    stroke(ctx, c => c.ellipse(0, 0, handOutline.rx, handOutline.ry, 0, 0, TAU), handOutline.strokeWidth / scale);
    ctx.restore();
  }

  function drawFoot(ctx, x, y, rotation) {
    // 小脚沿用圆手的奶油白、暖色底和 2.2 描边；宽 15、高 8.2，置于身体后面。
    ctx.save();
    ctx.translate(x, y); ctx.rotate(rotation * Math.PI / 180);
    ellipse(ctx, 0, 0, footOutline.rx, footOutline.ry, '#FFFDF8');
    ctx.save();
    ctx.beginPath(); ctx.ellipse(0, 0, footOutline.rx, footOutline.ry, 0, 0, TAU); ctx.clip();
    ellipse(ctx, 0, 2.5, 6.5, 1.5, '#F4EBDD');
    ctx.restore();
    stroke(ctx, c => c.ellipse(0, 0, footOutline.rx, footOutline.ry, 0, 0, TAU), footOutline.strokeWidth);
    ctx.restore();
  }

  function walkFeet(state) {
    return [
      { x: 38 - 5.5 * state.leftStep, y: 93.2 - 5.8 * state.leftStep, rotation: 4 * state.leftStep },
      { x: 62 + 5.5 * state.rightStep, y: 93.2 - 5.8 * state.rightStep, rotation: -4 * state.rightStep }
    ];
  }

  function drawCup(ctx, state) {
    ctx.save();
    ctx.translate(state.cupX, state.cupY);
    ctx.rotate(state.cupRotation * Math.PI / 180);
    // 杯身中心为原点，宽 15、高 18.4；比上一轮约大 15%，描边仍为 2.2。
    const body = c => {
      c.moveTo(-7.5, -9.2); c.quadraticCurveTo(0, -11.5, 7.5, -9.2);
      c.lineTo(6.35, 6.1); c.quadraticCurveTo(6.1, 9.2, 3.2, 9.2);
      c.lineTo(-3.2, 9.2); c.quadraticCurveTo(-6.1, 9.2, -6.35, 6.1);
      c.closePath();
    };
    ctx.beginPath(); body(ctx); ctx.fillStyle = '#FFFDF8'; ctx.fill();
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(-6.1, -8.6); ctx.quadraticCurveTo(0, -10, 6.1, -8.6);
    ctx.lineTo(5, 5.9); ctx.quadraticCurveTo(4.8, 7.7, 3, 7.7);
    ctx.lineTo(-3, 7.7); ctx.quadraticCurveTo(-4.8, 7.7, -5, 5.9);
    ctx.closePath(); ctx.clip();
    // 裁剪区域随杯子转，水与高光反向抵消杯倾角及身体后仰，保持画面水平。
    ctx.rotate(-(state.cupRotation + 2.5 * state.lift) * Math.PI / 180);
    ctx.fillStyle = '#9DD3EC'; ctx.fillRect(-24, -3.6, 48, 28);
    stroke(ctx, c => { c.moveTo(-4.2, -1.7); c.quadraticCurveTo(-2.6, -1.3, -0.9, -1.7); }, 1.1, '#FFFFFF');
    ctx.restore();
    stroke(ctx, body, 2.2);
    stroke(ctx, c => c.ellipse(0, -9.2, 7.5, 1.9, 0, 0, TAU), 2.2);
    ctx.restore();
  }

  function drawTrail(ctx, t) {
    // 按历史时间取样，圆点沿与手相同的缓动轨道逐个变小、变淡。
    for (let i = 6; i >= 1; i--) {
      const angle = circleAngle(t - i * 0.18);
      const x = 83 + 7 * Math.cos(angle), y = 48 + 8 * Math.sin(angle);
      const radius = 2.2 - i * 0.16;
      ctx.save(); ctx.globalAlpha = 0.9 - i * 0.08;
      ellipse(ctx, x, y, radius, radius, '#FFFDF8');
      stroke(ctx, c => c.arc(x, y, radius, 0, TAU), 0.65);
      ctx.restore();
    }
  }

  function draw(ctx, motion, t) {
    const state = frame(motion, t);
    ctx.save();
    if (motion === 'walk') {
      // 先画脚，着地脚不随身体摇摆；上半截由随后绘制的身体自然遮住。
      // 地面为 y=98.4（含描边）；外移增加到 5.5，倾角收为 4°，兼顾露出面积与手脚间距。
      for (const foot of walkFeet(state)) drawFoot(ctx, foot.x, foot.y, foot.rotation);
      ctx.translate(50 + state.walkShift, 93 - state.walkBob);
      ctx.rotate(state.walkSway * Math.PI / 180);
      ctx.scale(1, 1 - state.walkSquash);
      ctx.translate(-50, -93);
    }
    if (motion === 'closeEyes') {
      ctx.translate(50, 93);
      ctx.scale(1 - 0.012 * state.breath, 1 + 0.025 * state.breath);
      ctx.translate(-50, -93);
    }
    if (motion === 'lookFar') {
      ctx.translate(50, 93);
      ctx.rotate(3.5 * state.gaze * Math.PI / 180);
      ctx.translate(-50, -93);
    }
    if (motion === 'drinkWater') {
      ctx.translate(50, 93);
      ctx.rotate(2.5 * state.lift * Math.PI / 180);
      ctx.translate(-50, -93);
    }
    drawBody(ctx);
    drawLeaves(ctx);
    drawFace(ctx, motion, state);
    if (motion === 'lookFar') drawArm(ctx, 85, 74, 98, 58, 68 + 2.8 * state.gaze, 43 - 3.7 * state.gaze);
    if (motion === 'closeEyes') {
      drawArm(ctx, 15, 74, 4, 64, 26.5, 58 - 0.7 * state.breath);
      drawArm(ctx, 85, 74, 96, 64, 73.5, 58 - 0.7 * state.breath);
    }
    if (motion === 'rollEyes') drawArm(ctx, 85, 74, 98, 58, 83 + 7 * Math.cos(state.angle), 48 + 8 * Math.sin(state.angle));
    if (motion === 'walk') {
      const w = state.walkSwing;
      const [left, right] = state.walkHands;
      // 肩根、控制点基准和外弯不变；纵向控制点按原比例跟随缩小后的摆幅。
      const backBend = 0.6 * walkHandMotion.backwardDrop, frontBend = 8.7 / 11.5 * walkHandMotion.forwardLift;
      drawArm(ctx, 15, 58.5, 7.5 - 1.5 * w, 72 + backBend * state.leftStep - frontBend * state.rightStep, left.x, left.y);
      drawArm(ctx, 85, 58.5, 92.5 - 1.5 * w, 72 + backBend * state.rightStep - frontBend * state.leftStep, right.x, right.y);
    }
    if (motion === 'drinkWater') {
      // 根部与其他右臂一致；肘部向下、向外弯，随抬杯和轻啜平滑移动。
      const bendX = 83 + 2.5 * state.lift;
      const bendY = 83 + 2.5 * state.lift - 0.5 * state.sip;
      drawArm(ctx, 85, 74, bendX, bendY, state.handX, state.handY);
      // 圆手压在杯身右侧约三分之一，露出杯沿、左壁、水面及高光。
      drawCup(ctx, state);
      drawHand(ctx, state.handX, state.handY, state.cupRotation, 0.9);
    }
    if (motion === 'rollEyes') drawTrail(ctx, t);
    if (motion === 'lookFar') drawHand(ctx, 68 + 2.8 * state.gaze, 43 - 3.7 * state.gaze, 8);
    if (motion === 'closeEyes') {
      const y = 58 - 0.7 * state.breath;
      const rotation = Math.atan2(y - 64, 22.5) * 180 / Math.PI;
      drawHand(ctx, 26.5, y, rotation);
      drawHand(ctx, 73.5, y, -rotation);
    }
    if (motion === 'rollEyes') {
      const x = 83 + 7 * Math.cos(state.angle), y = 48 + 8 * Math.sin(state.angle);
      drawHand(ctx, x, y, Math.atan2(y - 58, x - 98) * 180 / Math.PI);
    }
    if (motion === 'walk') {
      const w = state.walkSwing;
      const [left, right] = state.walkHands;
      // 腰部基准 y=75.8；局部峰值差 4.848，叠加原身体倾斜后步峰手心高低差约 0.667。
      drawHand(ctx, left.x, left.y, 10 * w);
      drawHand(ctx, right.x, right.y, -10 * w);
    }
    ctx.restore();
  }

  // 任一单位法向的正分离量都是欧氏间距下界；方向优化只收紧下界，不影响保守性。
  function separationLowerBound(separation) {
    const increment = TAU / 64;
    let bestAngle = 0, gap = -Infinity;
    for (let j = 0; j < 64; j++) {
      const normal = j * increment, candidate = separation(normal);
      if (candidate > gap) { gap = candidate; bestAngle = normal; }
    }
    let low = bestAngle - increment, high = bestAngle + increment;
    for (let j = 0; j < 36; j++) {
      const a = low + (high - low) / 3, b = high - (high - low) / 3;
      if (separation(a) < separation(b)) low = a; else high = b;
    }
    return Math.max(gap, separation((low + high) / 2));
  }

  // 离线运行：node Design/motion/tomato-motion.js --check-walk。浏览器不执行检查。
  function checkWalkClearance() {
    const duration = 3.6, intervals = 36000, step = duration / intervals;
    let minimum = { gap: Infinity };
    for (let i = 0; i <= intervals; i++) {
      const t = i * step, state = frame('walk', t);
      const angle = state.walkSway * Math.PI / 180;
      const c = Math.cos(angle), s = Math.sin(angle), scaleY = 1 - state.walkSquash;
      for (const [handIndex, hand] of state.walkHands.entries()) {
        if (Math.hypot(hand.x - 50, hand.y - 93) + handOutline.rx + handOutline.strokeWidth / 2 > 50) {
          throw new Error('手部轮廓超出速度界使用的支点半径，需重新推导连续周期误差。');
        }
        const rotation = (handIndex === 0 ? 10 : -10) * state.walkSwing * Math.PI / 180;
        const hc = Math.cos(rotation), hs = Math.sin(rotation);
        const x = 50 + state.walkShift + c * (hand.x - 50) - s * scaleY * (hand.y - 93);
        const y = 93 - state.walkBob + s * (hand.x - 50) + c * scaleY * (hand.y - 93);
        for (const [footIndex, foot] of walkFeet(state).entries()) {
          const a = foot.rotation * Math.PI / 180, fc = Math.cos(a), fs = Math.sin(a);
          // 沿单位法向投影两个凸形状。描边是曲线外扩的圆盘，不能给椭圆两轴直接加 1.1。
          const separation = normal => {
            const nx = Math.cos(normal), ny = Math.sin(normal);
            const qx = c * nx + s * ny, qy = (-s * nx + c * ny) * scaleY;
            const hx = hc * qx + hs * qy, hy = -hs * qx + hc * qy;
            const fx = fc * nx + fs * ny, fy = -fs * nx + fc * ny;
            return nx * (foot.x - x) + ny * (foot.y - y)
              - Math.hypot(handOutline.rx * hx, handOutline.ry * hy)
              - handOutline.strokeWidth / 2 * Math.hypot(qx, qy)
              - Math.hypot(footOutline.rx * fx, footOutline.ry * fy) - footOutline.strokeWidth / 2;
          };
          const gap = separationLowerBound(separation);
          if (gap < minimum.gap) minimum = { gap, t, hand: handIndex === 0 ? '左手' : '右手', foot: footIndex === 0 ? '左脚' : '右脚' };
        }
      }
    }
    // |w'|、|L'|、|R'| <= 2π/1.8 + π/(2×0.225) < 10.473，且 L/R 不同时变化。
    // 当前手心速度局部 <= max(2.4+3.687, .5+1.161)×10.473 < (2.5+11.5)×10.473。
    // 脚心 <= (5.5+5.8)×10.473；沿用下列更大的旧摆幅速度界，覆盖本轮较小的摆幅。
    // 身体平移/上浮 <= 3.5×10.473；角速度 <= 4.5°×10.473；缩放速度 <= .02π/.32。
    // 全周期 |x-50| <= 28、|y-93| <= 20.887，手轮廓距支点 <= hypot(28,20.887)+9.15 < 44.1 < 50。
    // 手旋转 <= 10°×10.473，脚旋转 <= 4°×10.473。
    // 各项相加 < 147+119+37+42+10+17+7=379，仍可取 400 单位/s 的保守总界。
    // 任意时刻到最近采样 <= step/2，因此扣除 .02，覆盖采样间的整个连续周期。
    const continuousLowerBound = minimum.gap - 400 * step / 2;
    return { passed: continuousLowerBound >= 2, duration, step, samples: intervals + 1,
      pairs: 4, minimum, continuousLowerBound, requiredGap: 2 };
  }

  // 两段二次曲线（含 round 描边）的凸包支撑函数；凸包只会让嘴的避让检查更保守。
  function mouthSupport(nx, ny) {
    let maximum = -Infinity;
    for (const [x0, y0, x1, y1, x2, y2] of faceOutline.mouth.curves) {
      const a = nx * x0 + ny * y0, b = nx * x1 + ny * y1, c = nx * x2 + ny * y2;
      maximum = Math.max(maximum, a, c);
      const denominator = a - 2 * b + c;
      const t = denominator === 0 ? -1 : (a - b) / denominator;
      if (t > 0 && t < 1) maximum = Math.max(maximum, (1 - t) ** 2 * a + 2 * t * (1 - t) * b + t * t * c);
    }
    return maximum + faceOutline.mouth.strokeWidth / 2 * Math.hypot(nx, ny);
  }

  function checkWalkFaceClearance() {
    const duration = 3.6, intervals = 36000, step = duration / intervals;
    const features = [
      ...faceOutline.eyes.map((eye, i) => ({ name: i === 0 ? '左眼（含眼白高光）' : '右眼（含眼白高光）', ...eye })),
      { name: '嘴（含描边）', support: mouthSupport }
    ];
    // 第 5 轮允许手掌与腮红重叠；只检查双眼和嘴，不再限制手掌相对腮红的高度。
    let minimum = { gap: Infinity };
    for (let i = 0; i <= intervals; i++) {
      const t = i * step, state = frame('walk', t);
      const scaleY = 1 - state.walkSquash;
      for (const [handIndex, hand] of state.walkHands.entries()) {
        const rotation = (handIndex === 0 ? 10 : -10) * state.walkSwing * Math.PI / 180;
        const hc = Math.cos(rotation), hs = Math.sin(rotation);
        // 脸与手共享身体变换，消去共同平移与旋转后，只需保留纵向压扁和手掌自转。
        const handSupport = (nx, ny) => Math.hypot(handOutline.rx * (hc * nx + hs * ny), handOutline.ry * (-hs * nx + hc * ny))
          + handOutline.strokeWidth / 2 * Math.hypot(nx, ny);
        for (const feature of features) {
          const gap = separationLowerBound(normal => {
            const nx = Math.cos(normal), ny = Math.sin(normal) * scaleY;
            const featureSupport = feature.support ? feature.support(-nx, -ny)
              : -nx * feature.x - ny * feature.y + Math.hypot(feature.rx * nx, feature.ry * ny);
            return -nx * hand.x - ny * hand.y - handSupport(nx, ny) - featureSupport;
          });
          if (gap < minimum.gap) minimum = { gap, t, hand: handIndex === 0 ? '左手' : '右手', feature: feature.name };
        }
      }
    }
    // 脸与手共享身体变换；相对速度比手脚检查更低，统一用 400 单位/s 扣除 .02 采样误差。
    // openEye 的大小高光本身完全位于眼睛椭圆内，眼睛外轮廓已完整包住眼白及高光。
    const continuousLowerBound = minimum.gap - 400 * step / 2;
    return { passed: continuousLowerBound >= 2,
      duration, step, samples: intervals + 1, pairs: features.length * 2, minimum, continuousLowerBound, requiredGap: 2 };
  }

  // 以真实描边外扩曲线取样成凸多边形；不是直接把椭圆两轴加上半描边。
  function ellipseOutline(x, y, rx, ry, radius, segments) {
    return Array.from({ length: segments }, (_, i) => {
      const angle = TAU * i / segments, c = Math.cos(angle), s = Math.sin(angle);
      const normalLength = Math.hypot(c / rx, s / ry);
      return { x: x + rx * c + radius * c / rx / normalLength,
        y: y + ry * s + radius * s / ry / normalLength };
    });
  }

  function polygonArea(points) {
    let sum = 0;
    for (let i = 0; i < points.length; i++) {
      const a = points[i], b = points[(i + 1) % points.length];
      sum += a.x * b.y - a.y * b.x;
    }
    return Math.abs(sum) / 2;
  }

  function intersectConvex(subject, clip) {
    let result = subject;
    for (let i = 0; i < clip.length && result.length; i++) {
      const a = clip[i], b = clip[(i + 1) % clip.length], input = result;
      const side = p => (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
      result = [];
      let previous = input[input.length - 1], previousSide = side(previous);
      for (const current of input) {
        const currentSide = side(current);
        if ((currentSide >= 0) !== (previousSide >= 0)) {
          const fraction = previousSide / (previousSide - currentSide);
          result.push({ x: previous.x + fraction * (current.x - previous.x),
            y: previous.y + fraction * (current.y - previous.y) });
        }
        if (currentSide >= 0) result.push(current);
        previous = current; previousSide = currentSide;
      }
    }
    return result;
  }

  function checkWalkVisibility(segments = 1024) {
    const duration = 3.6, intervals = 3600, step = duration / intervals;
    // drawBody 先描边 4.8 再填充，遮挡轮廓为椭圆向外平行偏移 2.4。
    const body = ellipseOutline(50, 60, 38, 33, 2.4, segments);
    const footShapes = [footOutline.strokeWidth / 2, 0].map(radius =>
      ellipseOutline(0, 0, footOutline.rx, footOutline.ry, radius, segments));
    const transform = (points, x, y, angle, scaleY = 1, pivotX = 0, pivotY = 0) => {
      const c = Math.cos(angle), s = Math.sin(angle);
      return points.map(p => ({ x: x + c * (p.x - pivotX) - s * scaleY * (p.y - pivotY),
        y: y + s * (p.x - pivotX) + c * scaleY * (p.y - pivotY) }));
    };
    const visibleAreas = (state, foot, shape) => {
      const mask = transform(body, 50 + state.walkShift, 93 - state.walkBob,
        state.walkSway * Math.PI / 180, 1 - state.walkSquash, 50, 93);
      const outline = transform(shape, foot.x, foot.y, foot.rotation * Math.PI / 180);
      return polygonArea(outline) - polygonArea(intersectConvex(outline, mask));
    };
    const standing = frame('walk', 0), standingFoot = walkFeet(standing)[0];
    const baseline = footShapes.map(shape => visibleAreas(standing, standingFoot, shape));
    const minimumLifted = footShapes.map(() => ({ area: Infinity }));
    const minimumDelta = footShapes.map(() => Infinity);
    let liftedSamples = 0;
    for (let i = 0; i <= intervals; i++) {
      const t = i * step, state = frame('walk', t);
      for (const [index, foot] of walkFeet(state).entries()) {
        const lift = index === 0 ? state.leftStep : state.rightStep;
        if (lift <= 1e-12) continue; // 排除正弦浮点残差造成的假抬脚。
        liftedSamples++;
        footShapes.forEach((shape, kind) => {
          const area = visibleAreas(state, foot, shape);
          minimumDelta[kind] = Math.min(minimumDelta[kind], area - baseline[kind]);
          if (area < minimumLifted[kind].area) minimumLifted[kind] = { area, t, foot: index === 0 ? '左脚' : '右脚' };
        });
      }
    }
    const peakState = frame('walk', representativeTime.walk), peakFoot = walkFeet(peakState)[0];
    const peak = footShapes.map(shape => visibleAreas(peakState, peakFoot, shape));
    const angle = peakFoot.rotation * Math.PI / 180;
    const groundGap = 98.4 - peakFoot.y
      - Math.hypot(footOutline.rx * Math.sin(angle), footOutline.ry * Math.cos(angle)) - footOutline.strokeWidth / 2;
    // 面积为数值多边形近似；与间距的连续保守证明分开报告，允许加倍分辨率复核。
    return { passed: minimumDelta.every(delta => delta >= 0), duration, step, samples: intervals + 1,
      liftedSamples, segments, areaKinds: ['含描边外轮廓', '填充区域'], baseline, minimumLifted, minimumDelta,
      peak, peakRatio: peak.map((area, i) => area / baseline[i]), groundGap, groundGapAt76px: groundGap * 0.76 };
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { frame, draw, representativeTime, checkWalkClearance, checkWalkFaceClearance, checkWalkVisibility };
    if (process.argv.includes('--check-walk')) {
      const clearance = checkWalkClearance(), faceClearance = checkWalkFaceClearance(), visibility = checkWalkVisibility();
      console.log(JSON.stringify({ clearance, faceClearance, visibility }, null, 2));
      process.exitCode = clearance.passed && faceClearance.passed && visibility.passed ? 0 : 1;
    }
    return;
  }

  const canvases = [...document.querySelectorAll('canvas[data-motion]')];
  const query = new URLSearchParams(location.search).get('still');
  const fixedTime = query !== null && query.trim() !== '' && Number.isFinite(Number(query)) && Number(query) >= 0 ? Number(query) : null;
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  const startedAt = performance.now();
  let animationID = null;

  function render(now) {
    const t = (now - startedAt) / 1000;
    for (const canvas of canvases) {
      const ratio = window.devicePixelRatio || 1;
      const pixels = Math.max(1, Math.round(canvas.clientWidth * ratio));
      if (canvas.width !== pixels || canvas.height !== pixels) { canvas.width = pixels; canvas.height = pixels; }
      const ctx = canvas.getContext('2d');
      ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, pixels, pixels);
      ctx.setTransform(pixels / 100, 0, 0, pixels / 100, 0, 0);
      const motion = canvas.dataset.motion;
      const time = canvas.hasAttribute('data-reduced') ? representativeTime[motion] : fixedTime ?? (reduced.matches ? representativeTime[motion] : t);
      draw(ctx, motion, time);
    }
    document.getElementById('status').textContent = fixedTime !== null
      ? `动作演示和 76px 预览已固定在 ${fixedTime} 秒；静止代表帧一排始终显示各动作的代表时刻。`
      : reduced.matches ? '系统已启用减少动态效果，六个动作均显示静止代表帧。' : '六个动作同步计时、循环播放。添加 ?still=1.8 可停在指定秒数。';
    animationID = fixedTime === null && !reduced.matches ? requestAnimationFrame(render) : null;
  }

  function restart() {
    if (animationID !== null) cancelAnimationFrame(animationID);
    render(performance.now());
  }
  reduced.addEventListener('change', restart);
  window.addEventListener('resize', restart);
  restart();
})();
