// 菜单栏番茄仔图标：在 18×18 的坐标系里绘制，脸部表情随状态变化
// variant: 'filled'（模板实心，脸镂空）| 'outline'（模板线条）| 'color'（彩色）
// state:   'idle' | 'working' | 'awaiting' | 'resting'

const MB = 18;
const MB_INK = '#4A3428';

function mbBody(ctx) { ctx.beginPath(); ctx.ellipse(9, 10.7, 7.1, 6.3, 0, 0, Math.PI * 2); }

function mbLeaf(ctx) {
  ctx.beginPath();
  ctx.ellipse(6.6, 4.5, 2.7, 1.15, -0.35, 0, Math.PI * 2);
  ctx.moveTo(14.1, 4.5);
  ctx.ellipse(11.4, 4.5, 2.7, 1.15, 0.35, 0, Math.PI * 2);
  ctx.moveTo(9.6, 1.4);
  ctx.roundRect(8.4, 1.4, 1.2, 3.6, 0.6);
}

function mbFace(ctx, state, color, lineWidth = 1.05) {
  ctx.fillStyle = color;
  ctx.strokeStyle = color;
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  const eyes = [6.5, 11.5];
  switch (state) {
    case 'idle': // 困困的「- -」
      ctx.beginPath();
      for (const x of eyes) { ctx.moveTo(x - 1.1, 10.9); ctx.lineTo(x + 1.1, 10.9); }
      ctx.stroke();
      break;
    case 'working': // 认真的圆眼睛
      for (const x of eyes) { ctx.beginPath(); ctx.arc(x, 10.6, 1.1, 0, Math.PI * 2); ctx.fill(); }
      break;
    case 'awaiting': // 睁大眼睛 + 「o」嘴，喊你休息
      for (const x of eyes) { ctx.beginPath(); ctx.arc(x, 10.1, 1.25, 0, Math.PI * 2); ctx.fill(); }
      ctx.beginPath(); ctx.arc(9, 13.4, 0.85, 0, Math.PI * 2); ctx.fill();
      break;
    case 'resting': // 眯眼笑「^ ^」
      ctx.beginPath();
      for (const x of eyes) { ctx.moveTo(x - 1.2, 11.3); ctx.quadraticCurveTo(x, 9.3, x + 1.2, 11.3); }
      ctx.stroke();
      break;
  }
}

function drawMenuIcon(canvas, cssSize, variant, state, fg) {
  const dpr = window.devicePixelRatio || 1;
  canvas.width = canvas.height = Math.round(cssSize * dpr);
  canvas.style.width = canvas.style.height = cssSize + 'px';
  const ctx = canvas.getContext('2d');
  ctx.setTransform(cssSize * dpr / MB, 0, 0, cssSize * dpr / MB, 0, 0);

  if (variant === 'filled') {
    ctx.fillStyle = fg;
    mbBody(ctx); ctx.fill();
    // 叶子与果身之间留一道缝，小尺寸下也分得清
    ctx.globalCompositeOperation = 'destination-out';
    mbLeaf(ctx); ctx.lineWidth = 1.6; ctx.stroke();
    mbFace(ctx, state, '#000');
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = fg;
    mbLeaf(ctx); ctx.fill();
  } else if (variant === 'outline') {
    ctx.strokeStyle = fg; ctx.lineWidth = 1.35;
    mbBody(ctx); ctx.stroke();
    ctx.globalCompositeOperation = 'destination-out';
    mbLeaf(ctx); ctx.lineWidth = 1.4; ctx.stroke();
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = fg; mbLeaf(ctx); ctx.fill();
    mbFace(ctx, state, fg);
  } else {
    ctx.lineJoin = 'round';
    mbBody(ctx);
    ctx.fillStyle = '#F0543F'; ctx.fill();
    ctx.strokeStyle = MB_INK; ctx.lineWidth = 1.1; ctx.stroke();
    ctx.beginPath(); ctx.ellipse(6.4, 8.2, 1.6, 0.8, -0.5, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,.55)'; ctx.fill();
    mbLeaf(ctx);
    ctx.lineWidth = 1.6; ctx.strokeStyle = MB_INK; ctx.stroke();
    ctx.fillStyle = '#5BCB6E'; ctx.fill();
    for (const x of [4.6, 13.4]) { ctx.beginPath(); ctx.ellipse(x, 13, 1.2, 0.7, 0, 0, Math.PI * 2); ctx.fillStyle = 'rgba(255,120,140,.6)'; ctx.fill(); }
    mbFace(ctx, state, MB_INK);
  }
}
