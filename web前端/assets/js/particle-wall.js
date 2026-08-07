/* ================================================================
   ParticleWall — 粒子光影幕墙
   用法: const pw = new ParticleWall(document.getElementById("wall"), { spacingDesktop: 30 });
   ================================================================ */
class ParticleWall {
  constructor(container, options = {}) {
    this.container = container;
    this.options = Object.assign({
      spacingDesktop: 38,   // 桌面端粒子间距（越小越密）
      spacingLaptop: 34,     // 笔记本间距
      spacingMobile: 28,     // 手机端间距
      mouseRadius: 240,      // 鼠标影响半径
      returnForce: 0.006,    // 回弹力度（越小飘得越远）
      damping: 0.955,       // 阻尼系数（越大惯性越大）
      connectDist: 100,      // 连线最大距离
      particleAlpha: 0.5,   // 粒子透明度
      lineAlpha: 0.12,       // 连线透明度
      glowAlpha: 0.08,       // 光晕透明度
    }, options);

    this.canvas = container.querySelector('.particle-wall__canvas');
    this.light = container.querySelector('.particle-wall__light');
    if (!this.canvas) return;

    this.ctx = this.canvas.getContext('2d');
    this.particles = [];
    this.mouse = { x: -2000, y: -2000 };
    this.raf = null;

    this._onResize = this._onResize.bind(this);
    this._onMove = this._onMove.bind(this);
    this._onLeave = this._onLeave.bind(this);

    this._init();
  }

  _init() {
    this._resize();
    this._createParticles();
    window.addEventListener('resize', this._onResize);
    this.container.addEventListener('mousemove', this._onMove);
    this.container.addEventListener('mouseleave', this._onLeave);
    this._animate();
  }

  _resize() {
    const r = this.container.getBoundingClientRect();
    this.canvas.width = r.width;
    this.canvas.height = r.height;
  }

  _onResize() {
    this._resize();
    this._createParticles();
  }

  _getSpacing() {
    const w = window.innerWidth;
    if (w < 768) return this.options.spacingMobile;
    if (w < 1200) return this.options.spacingLaptop;
    return this.options.spacingDesktop;
  }

  _createParticles() {
    const s = this._getSpacing();
    const cols = Math.floor(this.canvas.width / s) + 1;
    const rows = Math.floor(this.canvas.height / s) + 1;
    this.particles = [];

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const cx = c * s + (s - this.options.spacingDesktop) / 2;
        const cy = r * s + (s - this.options.spacingDesktop) / 2;
        this.particles.push({
          x: cx + (Math.random() - .5) * s * .4,
          y: cy + (Math.random() - .5) * s * .4,
          ox: cx,
          oy: cy,
          vx: 0, vy: 0,
          r: Math.random() * 1.4 + .4,
        });
      }
    }
  }

  _onMove(e) {
    const r = this.canvas.getBoundingClientRect();
    this.mouse.x = e.clientX - r.left;
    this.mouse.y = e.clientY - r.top;
    if (this.light) {
      this.light.style.left = e.clientX + 'px';
      this.light.style.top = e.clientY + 'px';
    }
  }

  _onLeave() {
    this.mouse.x = -2000;
    this.mouse.y = -2000;
  }

  _animate() {
    const ctx = this.ctx;
    const w = this.canvas.width;
    const h = this.canvas.height;
    const { mouseRadius, returnForce, damping, connectDist, particleAlpha, lineAlpha, glowAlpha } = this.options;

    ctx.clearRect(0, 0, w, h);

    // Update + draw particles
    for (const p of this.particles) {
      const dx = this.mouse.x - p.x;
      const dy = this.mouse.y - p.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < mouseRadius && dist > .1) {
        const f = (mouseRadius - dist) / mouseRadius;
        p.vx += (dx / dist) * f * .65;
        p.vy += (dy / dist) * f * .65;
      }

      p.vx += (p.ox - p.x) * returnForce;
      p.vy += (p.oy - p.y) * returnForce;
      p.vx *= damping;
      p.vy *= damping;
      p.x += p.vx;
      p.y += p.vy;

      // Draw point
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,255,255,' + particleAlpha + ')';
      ctx.fill();

      // Glow
      const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 4);
      g.addColorStop(0, 'rgba(79,140,255,' + glowAlpha + ')');
      g.addColorStop(1, 'transparent');
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r * 4, 0, Math.PI * 2);
      ctx.fillStyle = g;
      ctx.fill();
    }

    // Connection lines
    for (let i = 0; i < this.particles.length; i++) {
      for (let j = i + 1; j < this.particles.length; j++) {
        const a = this.particles[i], b = this.particles[j];
        const dx = a.x - b.x, dy = a.y - b.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < connectDist) {
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.strokeStyle = 'rgba(255,255,255,' + ((1 - dist / connectDist) * lineAlpha) + ')';
          ctx.lineWidth = .4;
          ctx.stroke();
        }
      }
    }

    this.raf = requestAnimationFrame(() => this._animate());
  }

  destroy() {
    cancelAnimationFrame(this.raf);
    window.removeEventListener('resize', this._onResize);
    this.container.removeEventListener('mousemove', this._onMove);
    this.container.removeEventListener('mouseleave', this._onLeave);
  }
}
