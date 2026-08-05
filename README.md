# 超越乙号新能源虚拟电站

去中心化虚拟电厂协同自治调控仿真平台。孤岛自治与分布式协同双模式。

## 快速启动

```bash
# 在项目根目录启动本地服务器
python -m http.server 8080
```

浏览器打开 `http://localhost:8080`

## 页面结构

| 页面 | 文件 | 说明 |
|------|------|------|
| 落地页 | `index.html` | 项目门户，9站邻域拓扑演示 |
| 孤岛控制舱 | `dashboard_island.html` | fmincon 六维优化，独立运行 |
| 协同控制舱 | `dashboard_cooperate.html` | ADMM 分布式协同，功率互济 |
| 技术架构 | `technology.html` | 三层架构 + 双模式算法说明 |
| 实验验证 | `validation.html` | V1.0→V2.0 指标演进 |

## 技术栈

- **仿真引擎**：MATLAB (fmincon SQP + ADMM + PI控制)
- **预测层**：Python (LightGBM + 光伏物理模型)
- **可视化**：原生 HTML/CSS/JS + Chart.js + PapaParse
- **设计系统**：CSS 令牌驱动，暖金主题

## 浏览器支持

Chrome / Edge / Firefox 最新版。需要本地服务器运行（CSV 和视频文件通过 fetch 加载）。
