# 超越乙号 VPP 页面拆分说明

## 新页面结构

- `index.html`：精简后的电影化落地页。保留原加载页和顶部三段视频 Hero，下方仅保留 4 个全屏章节。
- `technology.html`：系统架构、控制算法、三个 VPP 子站与数据闭环。
- `validation.html`：实验结果、指标演进、应用场景与工程成果。
- `dashboard.html`：原有孤岛自治控制舱，需与这些文件放在同一目录。
- `dashboard_cooperate.html`：原有协同控制舱，需与这些文件放在同一目录。

## 必须保留的同级资源

`frontend-bg.mp4`、`solar.mp4`、`wind.mp4`、`tidal.mp4`、`particle-wall.css`、`particle-wall.js`。

## 内容分配逻辑

落地页只回答四个问题：为什么需要系统、如何切换模式、在哪里验证、结果是否可信。技术细节与实验材料分别进入两个详情页，避免同一滚动流信息过载。
