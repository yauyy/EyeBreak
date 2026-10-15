'use strict';

(() => {
  // 与 TomatoCharacter.swift 使用同一套 100×100 坐标、配色和时间公式。
  const INK = '#4A3428';
  const TAU = Math.PI * 2;
  const representativeTime = { still: 0, lookFar: 1.8, blink: 0.78, closeEyes: 0, rollEyes: 1.5 };
  const phase = (t, duration) => ((t % duration) + duration) % duration;
  const ease = value => (1 - Math.cos(Math.PI * Math.max(0, Math.min(1, value)))) / 2;
  const circleAngle = t => -Math.PI / 2 + TAU * ease(phase(t, 3) / 3);

  function frame(motion, t) {
    const state = { lookX: 0, lookY: 0, closure: 0, gaze: 0, breath: 0, angle: 0 };
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

  function openEye(ctx, x, y, closure) {
    ctx.save();
    // 眼珠保持原尺寸，用上下眼皮围成的开口裁切，上眼皮真实落下。
    const top = y - 6.9 * (1 - closure);
    const bottom = y + 6.9 * (1 - closure);
    ctx.beginPath();
    ctx.moveTo(x - 5.9, top);
    ctx.quadraticCurveTo(x, top + 3 * closure, x + 5.9, top);
    ctx.lineTo(x + 5.9, bottom);
    ctx.quadraticCurveTo(x, bottom + 3 * closure, x - 5.9, bottom);
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
      stroke(ctx, c => { c.moveTo(x - 5.4, top); c.quadraticCurveTo(x, top + 3 * closure, x + 5.4, top); }, 2.2, `rgba(74,52,40,${closure})`);
    }
  }

  function drawFace(ctx, motion, state) {
    for (const x of [37, 63]) {
      if (motion === 'closeEyes') closedEye(ctx, x, 60);
      else openEye(ctx, x + state.lookX, 60 + state.lookY, state.closure);
    }
    for (const x of [28, 72]) ellipse(ctx, x, 69.7, 5.8, 3.2, 'rgba(255,110,140,.42)');
    stroke(ctx, c => {
      c.moveTo(46.6, 67.5); c.quadraticCurveTo(48.3, 71, 50, 67.5);
      c.quadraticCurveTo(51.7, 71, 53.4, 67.5);
    }, 1.8);
  }

  function drawArm(ctx, rootX, rootY, bendX, bendY, x, y) {
    const arm = c => { c.moveTo(rootX, rootY); c.quadraticCurveTo(bendX, bendY, x, y); };
    // 同一条二次曲线叠画成实心圆头管子；根部圆端与身体重叠。
    stroke(ctx, arm, 11);
    stroke(ctx, arm, 7, '#F0453A');
  }

  function drawHand(ctx, x, y, rotation) {
    // 手掌宽高比 1.15，高光和底部暖色随手掌旋转。
    ctx.save();
    ctx.translate(x, y); ctx.rotate(rotation * Math.PI / 180);
    ellipse(ctx, 0, 0, 8.05, 7, '#FFFDF8');
    ctx.save();
    ctx.beginPath(); ctx.ellipse(0, 0, 8.05, 7, 0, 0, TAU); ctx.clip();
    ellipse(ctx, 0, 4.1, 7, 2.6, '#F4EBDD');
    ellipse(ctx, -2.6, -3, 2.8, 1.6, '#FFFFFF', -32 * Math.PI / 180);
    ctx.restore();
    stroke(ctx, c => c.ellipse(0, 0, 8.05, 7, 0, 0, TAU), 2.2);
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
    drawBody(ctx);
    drawLeaves(ctx);
    drawFace(ctx, motion, state);
    if (motion === 'lookFar') drawArm(ctx, 85, 74, 98, 58, 68 + 2.8 * state.gaze, 43 - 3.7 * state.gaze);
    if (motion === 'closeEyes') {
      drawArm(ctx, 15, 74, 4, 64, 26.5, 58 - 0.7 * state.breath);
      drawArm(ctx, 85, 74, 96, 64, 73.5, 58 - 0.7 * state.breath);
    }
    if (motion === 'rollEyes') drawArm(ctx, 85, 74, 98, 58, 83 + 7 * Math.cos(state.angle), 48 + 8 * Math.sin(state.angle));
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
    ctx.restore();
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
      const pixels = Math.round(240 * ratio);
      if (canvas.width !== pixels || canvas.height !== pixels) { canvas.width = pixels; canvas.height = pixels; }
      const ctx = canvas.getContext('2d');
      ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.clearRect(0, 0, pixels, pixels);
      ctx.setTransform(pixels / 100, 0, 0, pixels / 100, 0, 0);
      const motion = canvas.dataset.motion;
      const time = canvas.hasAttribute('data-reduced') ? representativeTime[motion] : fixedTime ?? (reduced.matches ? representativeTime[motion] : t);
      draw(ctx, motion, time);
    }
    document.getElementById('status').textContent = fixedTime !== null
      ? `上排已固定在 ${fixedTime} 秒；下排显示各动作的静止代表帧。`
      : reduced.matches ? '系统已启用减少动态效果，两排均显示静止代表帧。' : '四个动作同步计时、循环播放。添加 ?still=1.8 可停在指定秒数。';
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
