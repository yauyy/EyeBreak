const W = 1024;
const INK = '#4A3428';
let K = 1; // 当前缩放：Canvas 的阴影模糊不随 transform 缩放，需要手动乘
let PLATE = true; // false 时只画角色本身（不带圆角底板、波点和柔光），用于 App 内的头像

const shadow = (ctx, color, blur, dy = 0) => { ctx.shadowColor = color; ctx.shadowBlur = blur * K; ctx.shadowOffsetY = dy * K; };
const lin = (ctx, x0, y0, x1, y1, stops) => { const g = ctx.createLinearGradient(x0, y0, x1, y1); stops.forEach((c, i) => g.addColorStop(i / (stops.length - 1), c)); return g; };
const rad = (ctx, x0, y0, r0, x1, y1, r1, stops) => { const g = ctx.createRadialGradient(x0, y0, r0, x1, y1, r1); stops.forEach((c, i) => g.addColorStop(i / (stops.length - 1), c)); return g; };
const ell = (ctx, x, y, rx, ry, rot = 0) => { ctx.moveTo(x + rx * Math.cos(rot), y + rx * Math.sin(rot)); ctx.ellipse(x, y, rx, ry, rot, 0, Math.PI * 2); };
const deg = d => d * Math.PI / 180;

function fillEll(ctx, x, y, rx, ry, color, rot = 0) { ctx.beginPath(); ell(ctx, x, y, rx, ry, rot); ctx.fillStyle = color; ctx.fill(); }

// 先用两倍线宽描边、再填充：多个形状合并后只保留外轮廓，得到贴纸般的粗描边
function blob(ctx, build, fill, { outline = 18, drop = true } = {}) {
  ctx.save();
  if (drop) shadow(ctx, 'rgba(60,30,10,.25)', 28, 12);
  ctx.beginPath(); build(ctx);
  ctx.lineJoin = 'round'; ctx.lineWidth = outline * 2; ctx.strokeStyle = INK; ctx.stroke();
  ctx.restore();
  ctx.beginPath(); build(ctx); ctx.fillStyle = fill; ctx.fill();
}

function stroke(ctx, build, width, color = INK) {
  ctx.beginPath(); build(ctx);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.lineWidth = width; ctx.strokeStyle = color; ctx.stroke();
}

// 闪亮大眼：深色椭圆 + 一大一小两个高光 + 底部反光
function eye(ctx, x, y, rx, ry, iris = '#3B2A22') {
  fillEll(ctx, x, y, rx, ry, iris);
  ctx.save(); ctx.beginPath(); ell(ctx, x, y, rx, ry); ctx.clip();
  fillEll(ctx, x, y + ry * 0.85, rx * 0.95, ry * 0.5, 'rgba(255,255,255,.2)');
  ctx.restore();
  fillEll(ctx, x - rx * 0.28, y - ry * 0.36, rx * 0.4, ry * 0.32, '#fff');
  fillEll(ctx, x + rx * 0.36, y + ry * 0.32, rx * 0.17, rx * 0.17, '#fff');
}

const blush = (ctx, x, y, r = 44) => fillEll(ctx, x, y, r, r * 0.58, 'rgba(255,110,140,.42)');

// ω 形小嘴
const omega = (ctx, x, y, w, lw = 15) => stroke(ctx, c => { c.moveTo(x - w, y); c.quadraticCurveTo(x - w / 2, y + w, x, y); c.quadraticCurveTo(x + w / 2, y + w, x + w, y); }, lw);
// U 形微笑 / 闭眼
const curve = (ctx, x, y, w, depth, lw = 16, color = INK) => stroke(ctx, c => { c.moveTo(x - w, y); c.quadraticCurveTo(x, y + depth, x + w, y); }, lw, color);

function sparkle(ctx, x, y, r, color = '#fff') {
  ctx.beginPath();
  ctx.moveTo(x, y - r); ctx.quadraticCurveTo(x, y, x + r, y); ctx.quadraticCurveTo(x, y, x, y + r);
  ctx.quadraticCurveTo(x, y, x - r, y); ctx.quadraticCurveTo(x, y, x, y - r);
  ctx.fillStyle = color; ctx.fill();
}

function plate(ctx) { ctx.beginPath(); ctx.roundRect(100, 100, 824, 824, 185); }

// 圆角底板：渐变 + 波点 + 顶部柔光
function base(ctx, stops, dots, draw) {
  if (!PLATE) { draw(ctx); return; }
  ctx.save(); shadow(ctx, 'rgba(0,0,0,.25)', 32, 14);
  plate(ctx); ctx.fillStyle = lin(ctx, 0, 100, 0, 924, stops); ctx.fill();
  ctx.restore();
  ctx.save(); plate(ctx); ctx.clip();
  if (dots) {
    ctx.fillStyle = dots;
    for (let row = 0, y = 150; y < 930; y += 92, row++)
      for (let x = 150 + (row % 2) * 46; x < 930; x += 92) { ctx.beginPath(); ell(ctx, x, y, 10, 10); ctx.fill(); }
  }
  draw(ctx);
  ctx.fillStyle = lin(ctx, 0, 100, 0, 470, ['rgba(255,255,255,.25)', 'rgba(255,255,255,0)']);
  ctx.fillRect(100, 100, 824, 370);
  ctx.restore();
}

const ICONS = [
  {
    key: 'A-tomato', name: 'A 番茄仔', desc: '戴叶子帽的番茄宝宝，番茄钟本钟',
    draw(ctx) {
      base(ctx, ['#FFF3E8', '#FFCDB5'], 'rgba(255,255,255,.6)', () => {
        blob(ctx, c => ell(c, 512, 585, 290, 252), rad(ctx, 410, 470, 20, 512, 585, 330, ['#FF9A82', '#F0453A']));
        fillEll(ctx, 392, 470, 60, 30, 'rgba(255,255,255,.55)', deg(-32));
        fillEll(ctx, 452, 432, 13, 13, 'rgba(255,255,255,.7)');
        const petals = c => { for (const k of [-144, -72, 0, 72, 144]) { const a = deg(k - 90); ell(c, 512 + Math.cos(a) * 66, 345 + Math.sin(a) * 66, 74, 30, a); } };
        blob(ctx, petals, '#5BCB6E', { outline: 16, drop: false });
        stroke(ctx, c => { c.moveTo(512, 330); c.quadraticCurveTo(508, 270, 540, 240); }, 44);
        stroke(ctx, c => { c.moveTo(512, 330); c.quadraticCurveTo(508, 270, 540, 240); }, 16, '#3E9E52');
        eye(ctx, 418, 590, 42, 52);
        eye(ctx, 606, 590, 42, 52);
        blush(ctx, 352, 665); blush(ctx, 672, 665);
        omega(ctx, 512, 660, 24);
      });
    },
  },
  {
    key: 'B-eyeball', name: 'B 萌眼球', desc: '圆滚滚的大眼睛精灵，护眼主题最直白',
    draw(ctx) {
      base(ctx, ['#E2F4FF', '#9FD3FF'], 'rgba(255,255,255,.6)', () => {
        sparkle(ctx, 230, 250, 36); sparkle(ctx, 800, 300, 26); sparkle(ctx, 790, 820, 30);
        for (const [x1, y1, x2, y2] of [[420, 330, 395, 255], [512, 305, 512, 225], [604, 330, 629, 255]])
          stroke(ctx, c => { c.moveTo(x1, y1); c.lineTo(x2, y2); }, 30);
        blob(ctx, c => ell(c, 512, 565, 262, 262), rad(ctx, 440, 470, 30, 512, 565, 300, ['#FFFFFF', '#E6F0FA']));
        ctx.beginPath(); ell(ctx, 512, 545, 150, 150);
        ctx.fillStyle = rad(ctx, 470, 490, 10, 512, 545, 160, ['#8FDCFF', '#2F7FE8']); ctx.fill();
        ctx.lineWidth = 14; ctx.strokeStyle = INK; ctx.stroke();
        fillEll(ctx, 512, 545, 70, 70, '#22303F');
        fillEll(ctx, 466, 492, 44, 36, '#fff');
        fillEll(ctx, 566, 598, 18, 18, '#fff');
        blush(ctx, 330, 690, 40); blush(ctx, 694, 690, 40);
        curve(ctx, 512, 735, 34, 30, 15);
      });
    },
  },
  {
    key: 'C-clock', name: 'C 小闹钟', desc: '粉色闹钟宝宝，提醒你按时休息',
    draw(ctx) {
      base(ctx, ['#E6FCF2', '#ABEBCF'], 'rgba(255,255,255,.65)', () => {
        stroke(ctx, c => { c.moveTo(390, 840); c.lineTo(360, 880); c.moveTo(634, 840); c.lineTo(664, 880); }, 30);
        stroke(ctx, c => { c.moveTo(330, 245); c.quadraticCurveTo(512, 175, 694, 245); }, 22);
        blob(ctx, c => { ell(c, 345, 300, 78, 70, deg(-35)); ell(c, 679, 300, 78, 70, deg(35)); }, '#FFD54F', { drop: false });
        blob(ctx, c => ell(c, 512, 580, 272, 272), lin(ctx, 0, 310, 0, 850, ['#FFB4C6', '#FF7FA1']));
        ctx.beginPath(); ell(ctx, 512, 585, 210, 210); ctx.fillStyle = '#FFFDF8'; ctx.fill();
        ctx.lineWidth = 12; ctx.strokeStyle = INK; ctx.stroke();
        for (const a of [0, 90, 180, 270]) { const t = deg(a - 90); fillEll(ctx, 512 + Math.cos(t) * 178, 585 + Math.sin(t) * 178, 13, 13, '#F28AA5'); }
        eye(ctx, 440, 575, 34, 44);
        eye(ctx, 584, 575, 34, 44);
        blush(ctx, 392, 650, 36); blush(ctx, 632, 650, 36);
        curve(ctx, 512, 650, 26, 26, 14);
      });
    },
  },
  {
    key: 'D-cloud', name: 'D 困困云', desc: '闭眼打盹的小云朵，休息一下吧',
    draw(ctx) {
      base(ctx, ['#8C98FA', '#4C4FC4'], 'rgba(255,255,255,.12)', () => {
        ctx.save(); shadow(ctx, 'rgba(255,224,138,.8)', 40);
        ctx.beginPath(); ctx.rect(0, 0, W, W); ctx.arc(782, 252, 66, 0, Math.PI * 2, true); ctx.clip('evenodd');
        fillEll(ctx, 742, 290, 80, 80, '#FFE08A');
        ctx.restore();
        sparkle(ctx, 250, 300, 28); sparkle(ctx, 640, 200, 20); sparkle(ctx, 830, 470, 18);
        ctx.fillStyle = '#fff';
        ctx.font = '900 96px "Arial Rounded MT Bold", ui-rounded, sans-serif'; ctx.fillText('Z', 300, 330);
        ctx.font = '900 64px "Arial Rounded MT Bold", ui-rounded, sans-serif'; ctx.fillText('z', 400, 250);
        blob(ctx, c => { ell(c, 365, 590, 125, 120); ell(c, 512, 515, 170, 165); ell(c, 665, 585, 130, 125); c.moveTo(300, 600); c.roundRect(260, 560, 500, 175, 88); },
          lin(ctx, 0, 350, 0, 760, ['#FFFFFF', '#E3E7FF']));
        curve(ctx, 445, 595, 34, 32, 16);
        curve(ctx, 579, 595, 34, 32, 16);
        blush(ctx, 390, 655, 38); blush(ctx, 634, 655, 38);
        fillEll(ctx, 512, 665, 14, 16, INK);
      });
    },
  },
  {
    key: 'E-cat', name: 'E 远眺猫', desc: '橘猫睁大眼睛看远方',
    draw(ctx) {
      base(ctx, ['#FFF8DE', '#FFE08A'], 'rgba(255,255,255,.6)', () => {
        const head = c => {
          c.moveTo(285, 470); c.lineTo(300, 225); c.quadraticCurveTo(310, 195, 340, 215); c.lineTo(470, 340);
          c.moveTo(739, 470); c.lineTo(724, 225); c.quadraticCurveTo(714, 195, 684, 215); c.lineTo(554, 340);
          ell(c, 512, 590, 292, 245);
        };
        blob(ctx, head, lin(ctx, 0, 220, 0, 840, ['#FFC877', '#FF9F43']));
        ctx.beginPath(); ctx.moveTo(320, 270); ctx.lineTo(330, 390); ctx.lineTo(420, 350); ctx.closePath();
        ctx.moveTo(704, 270); ctx.lineTo(694, 390); ctx.lineTo(604, 350); ctx.closePath();
        ctx.fillStyle = '#FFB3BE'; ctx.fill();
        for (const x of [470, 512, 554]) stroke(ctx, c => { c.moveTo(x, 375); c.lineTo(x, 425); }, 16, '#E5822B');
        eye(ctx, 412, 575, 48, 58);
        eye(ctx, 612, 575, 48, 58);
        ctx.beginPath(); ctx.moveTo(492, 632); ctx.lineTo(532, 632); ctx.lineTo(512, 655); ctx.closePath();
        ctx.fillStyle = '#FF7A93'; ctx.fill();
        omega(ctx, 512, 662, 24, 13);
        stroke(ctx, c => {
          c.moveTo(330, 655); c.lineTo(215, 640); c.moveTo(330, 680); c.lineTo(220, 700);
          c.moveTo(694, 655); c.lineTo(809, 640); c.moveTo(694, 680); c.lineTo(804, 700);
        }, 11);
        blush(ctx, 360, 700, 40); blush(ctx, 664, 700, 40);
      });
    },
  },
  {
    key: 'F-sprout', name: 'F 小绿芽', desc: '头顶嫩芽的绿团子，清新护眼',
    draw(ctx) {
      base(ctx, ['#EEFCE8', '#BDEBA8'], 'rgba(255,255,255,.65)', () => {
        stroke(ctx, c => { c.moveTo(512, 380); c.quadraticCurveTo(505, 320, 515, 270); }, 44);
        stroke(ctx, c => { c.moveTo(512, 380); c.quadraticCurveTo(505, 320, 515, 270); }, 16, '#3FAE4A');
        blob(ctx, c => { ell(c, 440, 262, 82, 42, deg(20)); ell(c, 592, 245, 90, 46, deg(-25)); }, '#6CD66F', { outline: 16, drop: false });
        stroke(ctx, c => { c.moveTo(395, 245); c.lineTo(480, 275); c.moveTo(640, 225); c.lineTo(548, 262); }, 9, 'rgba(255,255,255,.55)');
        blob(ctx, c => { c.moveTo(250, 640); c.bezierCurveTo(250, 420, 380, 360, 512, 360); c.bezierCurveTo(644, 360, 774, 420, 774, 640); c.bezierCurveTo(774, 790, 660, 830, 512, 830); c.bezierCurveTo(364, 830, 250, 790, 250, 640); c.closePath(); },
          rad(ctx, 430, 480, 20, 512, 600, 330, ['#9BE77A', '#43B54E']));
        fillEll(ctx, 380, 470, 42, 24, 'rgba(255,255,255,.45)', deg(-35));
        eye(ctx, 430, 610, 38, 48);
        eye(ctx, 594, 610, 38, 48);
        blush(ctx, 362, 685, 40); blush(ctx, 662, 685, 40);
        curve(ctx, 512, 685, 28, 28, 15);
      });
    },
  },
];
